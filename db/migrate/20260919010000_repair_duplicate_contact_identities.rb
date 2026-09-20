# Keep recovery logic frozen in this migration, independent of future application models.
class RepairDuplicateContactIdentities < ActiveRecord::Migration[7.1] # rubocop:disable Metrics/ClassLength
  ARCHIVE = 'contact_identity_repair_audits'.freeze
  DIRECT_REFERENCES = %w[contact_id contact_inbox_id].freeze
  JSON_ATTRIBUTES = %w[additional_attributes custom_attributes].freeze
  POLYMORPHIC = {
    'messages' => %w[sender], 'notifications' => %w[primary_actor secondary_actor],
    'active_storage_attachments' => %w[record], 'taggings' => %w[taggable tagger],
    'access_tokens' => %w[owner], 'platform_app_permissibles' => %w[permissible],
    'audits' => %w[auditable associated user], 'agent_sessions' => %w[subject result],
    'captain_assistant_responses' => %w[documentable],
    'data_import_items' => %w[chatwoot_record], 'data_import_mappings' => %w[chatwoot_record]
  }.freeze
  INDEXES = {
    'index_contact_inboxes_on_inbox_id_and_source_id' => ['contact_inboxes', %w[inbox_id source_id]],
    'uniq_email_per_account_contact' => ['contacts', %w[email account_id]],
    'index_notification_subscriptions_on_identifier' => ['notification_subscriptions', %w[identifier]]
  }.freeze

  def up
    # Explicit transaction also protects invocations outside Rails' migrator.
    connection.transaction do
      prepare_repair
      validate_ownership!
      create_archive
      mapping = contact_mapping
      say "Contact identities to consolidate: #{mapping.size}"
      merge_contacts(mapping)
      clear_legacy_emails
      merge_inboxes
      merge_subscriptions
      refresh_counters
      INDEXES.each do |name, (table, columns)|
        # Rebuild only these three integrity constraints, under the same locks.
        remove_index table, name: name, if_exists: true
        add_index table, columns, name: name, unique: true
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Restore the reviewed backup and audit mappings; automatic unmerge is unsafe after new writes'
  end

  private

  def prepare_repair
    execute "SET LOCAL lock_timeout = '5s'"
    execute "SET LOCAL statement_timeout = '300s'"
    @references = references
    tables = (@references.map(&:first) + %w[contacts contact_inboxes conversations notification_subscriptions inboxes]).uniq.sort
    execute "LOCK TABLE #{tables.map { |t| qt(t) }.join(', ')} IN SHARE ROW EXCLUSIVE MODE"
    # Do not trust a possibly incomplete index when inventorying the heap.
    execute 'SET LOCAL enable_indexscan = off'
    execute 'SET LOCAL enable_indexonlyscan = off'
    execute 'SET LOCAL enable_bitmapscan = off'
    execute 'SET LOCAL enable_nestloop = off'
  end

  def qt(name)
    connection.quote_table_name(name)
  end

  def q(value)
    connection.quote(value)
  end

  def rows(sql)
    connection.select_all(sql).to_a
  end

  def create_archive
    return if table_exists?(ARCHIVE)

    create_table ARCHIVE do |t|
      t.string :source_table, null: false
      t.bigint :source_id, null: false
      t.jsonb :original_row, null: false
      t.bigint :retained_id
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index ARCHIVE, [:source_table, :source_id], unique: true, name: 'idx_contact_identity_repair_original'
  end

  def archive(table, predicate, retained_id = nil)
    execute <<~SQL.squish
      INSERT INTO #{ARCHIVE}(source_table,source_id,original_row,retained_id)
      SELECT #{q(table)},t.id,to_jsonb(t),#{retained_id || 'NULL'} FROM #{qt(table)} t WHERE #{predicate}
      ON CONFLICT (source_table,source_id) DO NOTHING
    SQL
  end

  def references
    connection.tables.reject { |t| t == ARCHIVE }.flat_map do |table|
      columns = connection.columns(table).map(&:name)
      result = DIRECT_REFERENCES.filter_map { |c| [table, c, nil] if columns.include?(c) }
      result + polymorphic_references(table, columns)
    end
  end

  def polymorphic_references(table, columns)
    POLYMORPHIC.fetch(table, []).filter_map do |prefix|
      id = "#{prefix}_id"
      type = "#{prefix}_type"
      [table, id, type] if columns.include?(id) && columns.include?(type)
    end
  end

  def validate_ownership!
    bad = connection.select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1 FROM contact_inboxes ci JOIN contacts c ON c.id=ci.contact_id JOIN inboxes i ON i.id=ci.inbox_id
        WHERE c.account_id<>i.account_id
      )
    SQL
    raise 'Cross-account contact inbox found; repair aborted' if bad
  end

  def contact_mapping
    pairs = rows(<<~SQL.squish)
      SELECT c.id, min(c.id) OVER (PARTITION BY c.account_id,lower(c.email)) AS root
      FROM contacts c WHERE c.email IS NOT NULL AND btrim(c.email)<>''
      UNION ALL
      SELECT ci.contact_id AS id, min(ci.contact_id) OVER (PARTITION BY ci.inbox_id,ci.source_id) AS root
      FROM contact_inboxes ci WHERE ci.contact_id IS NOT NULL
    SQL
    parents = {}
    pairs.each do |pair|
      a = root(parents, pair['id'].to_i)
      b = root(parents, pair['root'].to_i)
      parents[[a, b].max] = [a, b].min if a != b
    end
    parents.keys.index_with { |id| root(parents, id) }.reject { |id, keep| id == keep }
  end

  def root(parents, id)
    return id unless parents.key?(id)

    parents[id] = root(parents, parents[id])
  end

  def merge_contacts(mapping)
    mapping.group_by { |_id, keep| keep }.each do |keep, entries|
      merge_contact_group(keep, entries.map(&:first).sort)
    end
  end

  def merge_contact_group(keep, old_ids)
    records = rows("SELECT * FROM contacts WHERE id IN (#{([keep] + old_ids).join(',')}) ORDER BY id")
    raise 'Cross-account contact merge refused' unless records.pluck('account_id').uniq.size == 1

    records.each { |r| archive('contacts', "id=#{r['id']}", keep) }
    merged = merged_attributes(records)
    old_ids.each do |old|
      remap('Contact', old, keep)
      execute "DELETE FROM contacts WHERE id=#{old}"
    end
    assignments = merged.map { |key, value| "#{connection.quote_column_name(key)}=#{q(value.is_a?(Hash) ? value.to_json : value)}" }
    execute "UPDATE contacts SET #{assignments.join(',')} WHERE id=#{keep}"
  end

  def merged_attributes(records)
    merged = records.reverse.each_with_object({}) do |record, result|
      record.each { |key, value| merge_attribute(result, key, value) }
    end
    merged.except!('id', 'account_id', 'created_at', 'updated_at')
    merged['blocked'] = records.any? { |record| record['blocked'] } if merged.key?('blocked')
    merged['email'] = nil if merged['email'].to_s.strip.downcase.end_with?('@lid')
    merged
  end

  def merge_attribute(result, key, value)
    return if value.nil? || value == ''

    value = JSON.parse(value) if JSON_ATTRIBUTES.include?(key) && value.is_a?(String)
    result[key] = value.is_a?(Hash) ? (result[key] || {}).merge(value) : value
  end

  def remap(type, old, keep)
    @references.each do |table, column, discriminator|
      next unless relevant_reference?(type, column, discriminator)

      condition = "#{qt(column)}=#{old}"
      condition += " AND #{qt(discriminator)}=#{q(type)}" if discriminator
      next unless connection.select_value("SELECT EXISTS(SELECT 1 FROM #{qt(table)} WHERE #{condition})")

      archive(table, condition, keep)
      collapse_join_collisions(table, column, discriminator, old, keep) if type == 'Contact'
      execute "UPDATE #{qt(table)} SET #{qt(column)}=#{keep} WHERE #{condition}"
    end
  end

  def relevant_reference?(type, column, discriminator)
    discriminator || column == (type == 'Contact' ? 'contact_id' : 'contact_inbox_id')
  end

  def collapse_join_collisions(table, column, discriminator, old, keep)
    keys = case table
           when 'group_contacts' then %w[conversation_id]
           when 'active_storage_attachments' then %w[record_type name blob_id]
           when 'taggings' then %w[tag_id taggable_type context tagger_id tagger_type taggable_id] - [column]
           else return
           end
    # The two rows represent the same membership/attachment/tag, not different history.
    equality = keys.map { |key| "a.#{qt(key)} IS NOT DISTINCT FROM b.#{qt(key)}" }.join(' AND ')
    predicate = "a.#{qt(column)}=#{old} AND b.#{qt(column)}=#{keep} AND #{equality}"
    predicate += " AND a.#{qt(discriminator)}='Contact'" if discriminator
    if table == 'group_contacts'
      archive(table, "id IN (SELECT b.id FROM #{qt(table)} a JOIN #{qt(table)} b ON #{predicate})", keep)
      execute <<~SQL.squish
        UPDATE group_contacts b SET metadata=COALESCE(a.metadata,'{}'::jsonb)||COALESCE(b.metadata,'{}'::jsonb)
        FROM group_contacts a WHERE #{predicate}
      SQL
    end
    execute "DELETE FROM #{qt(table)} a USING #{qt(table)} b WHERE #{predicate}"
  end

  def clear_legacy_emails
    predicate = "lower(btrim(email)) LIKE '%@lid'"
    archive('contacts', predicate)
    execute "UPDATE contacts SET email=NULL WHERE #{predicate}"
  end

  def merge_inboxes
    duplicates = rows(<<~SQL.squish)
      SELECT id,keep FROM (
        SELECT id,min(id) OVER(PARTITION BY inbox_id,source_id) keep FROM contact_inboxes
      ) d WHERE id<>keep ORDER BY id
    SQL
    duplicates.each do |row|
      old, keep = row.values_at('id', 'keep').map(&:to_i)
      archive('contact_inboxes', "id IN (#{old},#{keep})", keep)
      remap('ContactInbox', old, keep)
      execute <<~SQL.squish
        UPDATE contact_inboxes b SET additional_attributes=a.additional_attributes||b.additional_attributes
        FROM contact_inboxes a WHERE a.id=#{old} AND b.id=#{keep}
      SQL
      execute "DELETE FROM contact_inboxes WHERE id=#{old}"
    end
  end

  def merge_subscriptions
    conflict = connection.select_value(<<~SQL.squish)
      SELECT EXISTS(SELECT 1 FROM notification_subscriptions WHERE identifier IS NOT NULL
      GROUP BY identifier HAVING count(DISTINCT user_id)>1 OR count(DISTINCT subscription_type)>1)
    SQL
    raise 'Notification identifier belongs to different users/types; repair aborted' if conflict

    # For the same user/device, retain the most recently updated registration and its keys.
    rows(<<~SQL.squish).each do |row|
      SELECT id,keep FROM (
        SELECT id,first_value(id) OVER(PARTITION BY identifier ORDER BY updated_at DESC,id DESC) keep
        FROM notification_subscriptions WHERE identifier IS NOT NULL
      ) d WHERE id<>keep
    SQL
      archive('notification_subscriptions', "id=#{row['id']}", row['keep'])
      execute "DELETE FROM notification_subscriptions WHERE id=#{row['id']}"
    end
  end

  def refresh_counters
    if table_exists?('tags') && column_exists?('tags', 'taggings_count')
      archive('tags', "id IN (SELECT (original_row->>'tag_id')::bigint FROM #{ARCHIVE} WHERE source_table='taggings')")
      execute <<~SQL.squish
        UPDATE tags SET taggings_count=(SELECT count(*) FROM taggings WHERE tag_id=tags.id)
        WHERE id IN (SELECT (original_row->>'tag_id')::bigint FROM #{ARCHIVE} WHERE source_table='taggings')
      SQL
    end
    return unless table_exists?('companies') && column_exists?('companies', 'contacts_count')

    archive('companies', "id IN (SELECT (original_row->>'company_id')::bigint FROM #{ARCHIVE} WHERE source_table='contacts')")
    execute <<~SQL.squish
      UPDATE companies SET contacts_count=(SELECT count(*) FROM contacts WHERE company_id=companies.id)
      WHERE id IN (SELECT (original_row->>'company_id')::bigint FROM #{ARCHIVE} WHERE source_table='contacts')
    SQL
  end
end
