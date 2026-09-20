require_relative '20260919010000_repair_duplicate_contact_identities'
require_relative '../../lib/conversations/history_merge'

# Follow-up for databases that already ran the contact repair. No application callbacks.
class ReconcileRepairedSingleConversations < RepairDuplicateContactIdentities
  include Conversations::HistoryMerge
  CONVERSATION_ARCHIVE = 'conversation_identity_repair_audits'.freeze

  def up
    connection.transaction do
      prepare_repair
      create_archive
      targets = conversation_targets
      say "Single-conversation aliases to consolidate: #{targets.size}"
      targets.each { |row| merge_conversation(row['id'].to_i, row['keep'].to_i) }
      refresh_label_counters
    end
  end

  private

  def conversation_targets
    rows(<<~SQL.squish)
      SELECT id,keep FROM (
        SELECT c.id,first_value(c.id) OVER (
          PARTITION BY c.account_id,c.inbox_id,c.contact_id,c."group",c.group_source_id
          ORDER BY c.created_at DESC,c.id DESC
        ) keep
        FROM conversations c
        JOIN inboxes i ON i.id=c.inbox_id AND i.account_id=c.account_id
        JOIN contact_inboxes ci ON ci.id=c.contact_inbox_id AND ci.contact_id=c.contact_id AND ci.inbox_id=c.inbox_id
        WHERE i.lock_to_single_conversation AND c.contact_id IN (
          SELECT retained_id FROM contact_identity_repair_audits
          WHERE source_table='contacts' AND retained_id IS NOT NULL
          UNION
          SELECT (original_row->>'contact_id')::bigint FROM contact_identity_repair_audits
          WHERE source_table='contact_inboxes'
        )
      ) candidates WHERE id<>keep ORDER BY id
    SQL
  end

  def prepare_repair
    super
    execute 'LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE' if table_exists?('users')
  end

  def references
    super + connection.tables.flat_map do |table|
      connection.columns(table).map(&:name).grep(/\A(?:target_)?conversation_id\z/).map { |column| [table, column, nil] }
    end
  end

  def create_archive
    return if table_exists?(CONVERSATION_ARCHIVE)

    create_table CONVERSATION_ARCHIVE do |t|
      t.string :source_table, null: false
      t.bigint :source_id, null: false
      t.jsonb :original_row, null: false
      t.bigint :retained_id
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index CONVERSATION_ARCHIVE, [:source_table, :source_id], unique: true, name: 'idx_conversation_identity_repair_original'
  end
end
