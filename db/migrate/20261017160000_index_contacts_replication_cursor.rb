class IndexContactsReplicationCursor < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :contacts, [:account_id, :updated_at, :id], name: 'idx_contacts_replication_cursor', algorithm: :concurrently
  end
end
