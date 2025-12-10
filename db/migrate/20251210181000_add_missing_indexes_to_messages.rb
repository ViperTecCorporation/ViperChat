class AddMissingIndexesToMessages < ActiveRecord::Migration[7.0]
  def change
    add_index :messages, :conversation_id,
              name: 'idx_messages_conversation_id',
              if_not_exists: true

    add_index :messages, :account_id,
              name: 'idx_messages_account_id',
              if_not_exists: true

    add_index :messages, :inbox_id,
              name: 'idx_messages_inbox_id',
              if_not_exists: true

    add_index :messages, :status,
              name: 'idx_messages_status',
              if_not_exists: true

    add_index :messages, :created_at,
              name: 'idx_messages_created_at',
              if_not_exists: true
  end
end
