class CreateWhatsappTemplateRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_template_requests do |t|
      t.references :account, null: false, type: :integer, foreign_key: { on_delete: :cascade }
      t.references :channel, null: false, foreign_key: { to_table: :channel_whatsapp, on_delete: :cascade }
      t.string :waba_id, null: false
      t.string :name, null: false
      t.string :language, null: false
      t.string :fingerprint, null: false
      t.string :state, null: false, default: 'dispatched'
      t.string :provider_template_id
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :whatsapp_template_requests, [:account_id, :waba_id, :name, :language], unique: true,
                                                                                      name: 'index_whatsapp_template_requests_on_identity'
  end
end
