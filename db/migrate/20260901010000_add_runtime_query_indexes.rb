class AddRuntimeQueryIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :contact_inboxes, [:inbox_id, :contact_id],
              name: 'idx_contact_inboxes_inbox_contact', algorithm: :concurrently, if_not_exists: true
    add_index :messages, [:conversation_id, :account_id, :created_at],
              name: 'idx_messages_conversation_account_created', order: { created_at: :desc },
              algorithm: :concurrently, if_not_exists: true
    add_index :contacts, :bsuid, name: 'idx_contacts_bsuid_trgm', using: :gin,
                                 opclass: :gin_trgm_ops, algorithm: :concurrently, if_not_exists: true
    add_index :contacts, :whatsapp_username, name: 'idx_contacts_whatsapp_username_trgm', using: :gin,
                                             opclass: :gin_trgm_ops, algorithm: :concurrently, if_not_exists: true
    remove_index :messages, name: 'index_messages_on_sender_type_and_sender_id',
                            algorithm: :concurrently, if_exists: true
  end

  def down
    remove_index :contact_inboxes, name: 'idx_contact_inboxes_inbox_contact', algorithm: :concurrently, if_exists: true
    remove_index :messages, name: 'idx_messages_conversation_account_created', algorithm: :concurrently, if_exists: true
    remove_index :contacts, name: 'idx_contacts_bsuid_trgm', algorithm: :concurrently, if_exists: true
    remove_index :contacts, name: 'idx_contacts_whatsapp_username_trgm', algorithm: :concurrently, if_exists: true
    add_index :messages, [:sender_type, :sender_id], name: 'index_messages_on_sender_type_and_sender_id',
                                                     algorithm: :concurrently, if_not_exists: true
  end
end
