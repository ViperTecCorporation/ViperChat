class CreateWhatsappManagementEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_management_events do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :integer
      t.references :channel, null: false, foreign_key: { to_table: :channel_whatsapp, on_delete: :cascade }
      t.references :inbox, foreign_key: { on_delete: :cascade }, type: :integer
      t.string :field, null: false
      t.string :digest, null: false, limit: 64
      t.string :state, null: false, default: 'recorded'
      t.string :reason
      t.jsonb :payload, null: false, default: {}
      t.boolean :truncated, null: false, default: false
      t.jsonb :details, null: false, default: {}
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :whatsapp_management_events, [:account_id, :channel_id, :field, :digest],
              unique: true, name: 'index_whatsapp_management_events_on_delivery'
    add_index :whatsapp_management_events, [:channel_id, :created_at]
    add_index :whatsapp_management_events, :expires_at
  end
end
