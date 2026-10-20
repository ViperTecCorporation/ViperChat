class CreateWhatsappMessageIdentities < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_message_identities do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.references :channel, null: false, foreign_key: { to_table: :channel_whatsapp, on_delete: :cascade }
      t.string :provider, null: false
      t.text :external_id, null: false
      t.text :provider_message_id
      t.jsonb :observations, null: false, default: {}
      t.timestamps
    end
    add_index :whatsapp_message_identities, [:inbox_id, :provider, :external_id], unique: true, name: 'idx_wa_identity_external'

    create_table :whatsapp_message_identity_links do |t|
      t.references :whatsapp_message_identity, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :whatsapp_message_identity_links, [:whatsapp_message_identity_id, :message_id], unique: true, name: 'idx_wa_identity_message'
  end
end
