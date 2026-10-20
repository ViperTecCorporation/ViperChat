class AddInitialMetaMessagesPolicy < ActiveRecord::Migration[7.1]
  def change
    change_table :whatsapp_inbox_links, bulk: true do |t|
      t.boolean :meta_initial_messages_enabled, default: false, null: false
      t.integer :meta_initial_messages_limit, default: 5, null: false
    end
    add_check_constraint :whatsapp_inbox_links, 'meta_initial_messages_limit BETWEEN 0 AND 1000', name: 'wa_link_initial_meta_limit'

    create_table :whatsapp_meta_cycle_slots do |t|
      t.references :account, type: :integer, null: false, foreign_key: { on_delete: :cascade }
      t.references :whatsapp_inbox_link, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, type: :integer, null: false, foreign_key: { on_delete: :cascade }
      t.references :message, type: :integer, foreign_key: { on_delete: :nullify }, index: { unique: true }
      t.integer :cycle, null: false
      t.datetime :activation_cutoff, null: false
      t.integer :position, null: false
      t.timestamps
    end
    add_index :whatsapp_meta_cycle_slots, [:whatsapp_inbox_link_id, :conversation_id, :cycle, :activation_cutoff, :position],
              unique: true, name: 'index_wa_meta_cycle_slots_on_budget'
  end
end
