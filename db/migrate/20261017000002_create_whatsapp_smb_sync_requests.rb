class CreateWhatsappSmbSyncRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_smb_sync_requests do |t|
      t.references :account, null: false, type: :integer, foreign_key: { on_delete: :cascade }
      t.references :channel, null: false, foreign_key: { to_table: :channel_whatsapp, on_delete: :cascade }
      t.string :phone_number_id, null: false
      t.string :waba_id, null: false
      t.string :sync_type, null: false
      t.string :state, null: false, default: 'prepared'
      t.string :request_id
      t.string :reason
      t.integer :history_max_age_days, null: false
      t.datetime :dispatched_at
      t.timestamps
    end
    add_index :whatsapp_smb_sync_requests, [:phone_number_id, :sync_type], unique: true, name: 'index_whatsapp_smb_sync_requests_on_phone_type'
  end
end
