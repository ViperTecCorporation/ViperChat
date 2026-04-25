class RemoveDuplicateHotTableIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    remove_index :messages, name: 'idx_messages_account_id', algorithm: :concurrently, if_exists: true
    remove_index :messages, name: 'idx_messages_conversation_id', algorithm: :concurrently, if_exists: true
    remove_index :messages, name: 'idx_messages_inbox_id', algorithm: :concurrently, if_exists: true
    remove_index :messages, name: 'idx_messages_created_at', algorithm: :concurrently, if_exists: true

    remove_index :active_storage_blobs, name: 'idx_blobs_key', algorithm: :concurrently, if_exists: true

    remove_index :conversation_participants, name: 'idx_conv_part_conversation_id', algorithm: :concurrently, if_exists: true
    remove_index :conversation_participants, name: 'idx_conv_part_user_id', algorithm: :concurrently, if_exists: true

    remove_index :notifications, name: 'idx_notifications_user_id', algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :messages, :account_id, name: 'idx_messages_account_id', algorithm: :concurrently, if_not_exists: true
    add_index :messages, :conversation_id, name: 'idx_messages_conversation_id', algorithm: :concurrently, if_not_exists: true
    add_index :messages, :inbox_id, name: 'idx_messages_inbox_id', algorithm: :concurrently, if_not_exists: true
    add_index :messages, :created_at, name: 'idx_messages_created_at', algorithm: :concurrently, if_not_exists: true

    add_index :active_storage_blobs, :key, name: 'idx_blobs_key', algorithm: :concurrently, if_not_exists: true

    add_index :conversation_participants, :conversation_id,
              name: 'idx_conv_part_conversation_id',
              algorithm: :concurrently,
              if_not_exists: true
    add_index :conversation_participants, :user_id,
              name: 'idx_conv_part_user_id',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :notifications, :user_id, name: 'idx_notifications_user_id', algorithm: :concurrently, if_not_exists: true
  end
end
