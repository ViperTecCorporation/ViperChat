class CreateScheduledMessageItems < ActiveRecord::Migration[7.1]
  def change
    create_table :scheduled_message_items do |t|
      t.references :scheduled_message, null: false, foreign_key: true
      t.references :message, foreign_key: true
      t.integer :position, null: false
      t.integer :status, null: false, default: 0
      t.text :content
      t.string :content_type, null: false, default: 'text'
      t.jsonb :content_attributes, null: false, default: {}
      t.jsonb :attachment_blob_ids, null: false, default: []
      t.boolean :voice_message, null: false, default: false
      t.text :error_message
      t.datetime :dispatched_at
      t.datetime :sent_at
      t.timestamps
    end

    add_index :scheduled_message_items, [:scheduled_message_id, :position], unique: true,
                                                                            name: 'idx_scheduled_message_items_position'
  end
end
