class AddUnoapiContactSync < ActiveRecord::Migration[7.1]
  def change
    change_table :channel_whatsapp, bulk: true do |t|
      t.boolean :contact_sync_enabled, default: false, null: false
      t.string :contact_sync_status, default: 'disabled', null: false
      t.string :contact_sync_cursor
      t.integer :contact_sync_processed_count, default: 0, null: false
      t.integer :contact_sync_failed_count, default: 0, null: false
      t.integer :contact_sync_total_count
      t.text :contact_sync_error
      t.datetime :contact_sync_started_at
      t.datetime :contact_sync_completed_at
      t.datetime :contact_sync_next_run_at
    end

    add_column :contact_inboxes, :additional_attributes, :jsonb, default: {}, null: false
    add_index :channel_whatsapp, [:provider, :contact_sync_enabled], name: 'index_whatsapp_on_provider_and_contact_sync'
  end
end
