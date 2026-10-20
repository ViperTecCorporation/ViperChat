class CreateWhatsappUnifiedMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_unified_messages do |t|
      t.references :whatsapp_inbox_link, null: false, foreign_key: { on_delete: :cascade }
      t.references :message, foreign_key: { on_delete: :nullify }
      t.text :original_id, null: false
      t.string :direction, null: false
      t.string :participant_key, null: false
      t.string :message_kind, null: false
      t.string :state, null: false, default: 'pending'
      t.string :lease_token
      t.datetime :lease_expires_at
      t.bigint :media_inbox_id
      t.timestamps
    end
    add_index :whatsapp_unified_messages, [:whatsapp_inbox_link_id, :original_id, :direction], unique: true, name: 'idx_wa_unified_original'
    create_aliases
  end

  def create_aliases
    create_table :whatsapp_unified_message_aliases do |t|
      t.references :whatsapp_unified_message, index: { name: 'idx_wa_unified_alias_message' }, foreign_key: { on_delete: :cascade }
      t.references :message, foreign_key: { on_delete: :cascade }
      t.references :whatsapp_message_identity, null: false, index: { unique: true, name: 'idx_wa_unified_alias_identity' },
                                               foreign_key: { on_delete: :cascade }
      t.timestamps
    end
  end
end
