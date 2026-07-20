class CreateScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :scheduled_messages do |t|
      add_associations(t)
      t.datetime :scheduled_at, null: false
      t.integer :status, null: false, default: 0
      t.text :reason
      t.text :content
      t.string :content_type
      t.jsonb :content_attributes, null: false, default: {}
      t.jsonb :attachment_blob_ids, null: false, default: []
      t.text :error_message
      t.datetime :sent_at
      t.timestamps
    end

    add_index :scheduled_messages, [:account_id, :scheduled_at, :status]
  end

  private

  def add_associations(table)
    table.references :account, null: false, foreign_key: true
    table.references :conversation, null: false, foreign_key: true
    table.references :target_conversation, foreign_key: { to_table: :conversations }
    table.references :contact, null: false, foreign_key: true
    table.references :inbox, null: false, foreign_key: true
    table.references :label, null: false, foreign_key: true
    table.references :created_by, null: false, foreign_key: { to_table: :users }
    table.references :sender, null: false, foreign_key: { to_table: :users }
    table.references :message, foreign_key: true
  end
end
