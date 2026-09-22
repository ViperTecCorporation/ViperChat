require_relative '20260919010000_repair_duplicate_contact_identities'
require_relative '../../lib/conversations/history_merge'

# Separate, transactional follow-up: the earlier identity repair already ran.
class RepairDuplicatePhoneContacts < RepairDuplicateContactIdentities
  include Conversations::HistoryMerge
  PHONE_ARCHIVE = 'phone_contact_repair_audits'.freeze

  def up
    # Upgrades only ensure audit storage. Bulk repairs require an explicit,
    # separately reviewed maintenance invocation, never db:migrate.
    create_archive
  end

  def repair!(confirmation:)
    raise ArgumentError, 'Review backup and affected records before merging' unless confirmation == 'MERGE_REVIEWED_CONTACTS'

    connection.transaction do
      prepare_repair
      execute 'LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE'
      validate_ownership!
      create_archive
      mapping = contact_mapping
      say "Phone contacts to consolidate: #{mapping.size}"
      merge_contacts(mapping)
      targets = conversation_targets(mapping.values.uniq)
      say "Single conversations to consolidate: #{targets.size}"
      targets.each { |row| merge_conversation(row['id'].to_i, row['keep'].to_i) }
      refresh_counters
    end
  end

  private

  def contact_mapping
    rows(<<~SQL.squish).to_h { |row| [row['id'].to_i, row['keep'].to_i] }
      WITH phones AS (
        SELECT c.id,c.account_id,regexp_replace(c.phone_number,'[^0-9]','','g') phone
        FROM contacts c WHERE c.phone_number ~ '^[+0-9().[:space:]-]+$'
        AND NOT EXISTS(SELECT 1 FROM contact_inboxes ci WHERE ci.contact_id=c.id AND ci.source_id LIKE '%@g.us')
        AND NOT EXISTS(SELECT 1 FROM conversations v WHERE v.contact_id=c.id AND v."group")
      ), candidates AS (
        SELECT id,min(id) OVER(PARTITION BY account_id,phone) keep
        FROM phones WHERE phone ~ '^[1-9][0-9]{7,14}$'
      ) SELECT id,keep FROM candidates WHERE id<>keep ORDER BY id
    SQL
  end

  def conversation_targets(contact_ids)
    return [] if contact_ids.empty?

    rows(<<~SQL.squish)
      SELECT id,keep FROM (
        SELECT c.id,first_value(c.id) OVER (
          PARTITION BY c.account_id,c.inbox_id,c.contact_id,c."group",c.group_source_id
          ORDER BY c.created_at DESC,c.id DESC
        ) keep
        FROM conversations c JOIN inboxes i ON i.id=c.inbox_id AND i.account_id=c.account_id
        JOIN contact_inboxes ci ON ci.id=c.contact_inbox_id AND ci.contact_id=c.contact_id AND ci.inbox_id=c.inbox_id
        WHERE i.lock_to_single_conversation AND c.contact_id IN (#{contact_ids.join(',')})
      ) candidates WHERE id<>keep ORDER BY id
    SQL
  end

  def references
    super + connection.tables.flat_map do |table|
      connection.columns(table).map(&:name).grep(/\A(?:target_)?conversation_id\z/).map { |column| [table, column, nil] }
    end
  end

  def create_archive
    return if table_exists?(PHONE_ARCHIVE)

    create_table PHONE_ARCHIVE do |t|
      t.string :source_table, null: false
      t.bigint :source_id, null: false
      t.jsonb :original_row, null: false
      t.bigint :retained_id
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index PHONE_ARCHIVE, [:source_table, :source_id], unique: true, name: 'idx_phone_contact_repair_original'
  end

  def archive(table, predicate, retained_id = nil)
    execute <<~SQL.squish
      INSERT INTO #{PHONE_ARCHIVE}(source_table,source_id,original_row,retained_id)
      SELECT #{q(table)},t.id,to_jsonb(t),#{retained_id || 'NULL'} FROM #{qt(table)} t WHERE #{predicate}
      ON CONFLICT (source_table,source_id) DO NOTHING
    SQL
  end

  def refresh_counters
    if table_exists?('tags') && column_exists?('tags', 'taggings_count')
      predicate = "id IN (SELECT (original_row->>'tag_id')::bigint FROM #{PHONE_ARCHIVE} WHERE source_table='taggings')"
      archive('tags', predicate)
      execute "UPDATE tags SET taggings_count=(SELECT count(*) FROM taggings WHERE tag_id=tags.id) WHERE #{predicate}"
    end
    return unless table_exists?('companies') && column_exists?('companies', 'contacts_count')

    predicate = "id IN (SELECT (original_row->>'company_id')::bigint FROM #{PHONE_ARCHIVE} WHERE source_table='contacts')"
    archive('companies', predicate)
    execute "UPDATE companies SET contacts_count=(SELECT count(*) FROM contacts WHERE company_id=companies.id) WHERE #{predicate}"
  end
end
