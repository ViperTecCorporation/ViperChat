class CreateWhatsappUnifiedEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_unified_events do |t|
      t.references :whatsapp_inbox_link, null: false, foreign_key: { on_delete: :cascade }
      t.references :whatsapp_message_identity, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :activation_cutoff, null: false
      t.string :state, null: false, default: 'pending'
      t.string :reason, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.timestamps
    end
    add_index :whatsapp_unified_events, [:whatsapp_inbox_link_id, :whatsapp_message_identity_id], unique: true, name: 'idx_wa_unified_event_identity'
    add_index :whatsapp_unified_events, [:state, :next_attempt_at], name: 'idx_wa_unified_event_due'
  end
end
