class CreateWhatsappInboxLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_inbox_links do |t|
      t.references :account, null: false, foreign_key: true
      t.references :primary_inbox, null: false, foreign_key: { to_table: :inboxes, on_delete: :cascade }
      t.references :secondary_inbox, null: false, foreign_key: { to_table: :inboxes, on_delete: :cascade }
      t.string :default_provider, null: false
      t.boolean :enabled, null: false, default: false
      t.datetime :activated_at
      t.timestamps
    end
    add_index :whatsapp_inbox_links, :primary_inbox_id, unique: true, where: 'enabled', name: 'idx_wa_link_active_primary'
    add_index :whatsapp_inbox_links, :secondary_inbox_id, unique: true, where: 'enabled', name: 'idx_wa_link_active_secondary'
    add_check_constraint :whatsapp_inbox_links, 'primary_inbox_id <> secondary_inbox_id', name: 'wa_link_distinct_inboxes'
    add_check_constraint :whatsapp_inbox_links, "default_provider IN ('unoapi', 'whatsapp_cloud')", name: 'wa_link_provider'
    add_check_constraint :whatsapp_inbox_links, 'NOT enabled OR activated_at IS NOT NULL', name: 'wa_link_activation_cutoff'
  end
end
