class CreateWhatsappIdentityResolutions < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_identity_resolutions do |t|
      t.references :whatsapp_message_identity, null: false, index: { unique: true, name: 'idx_wa_resolution_identity' },
                                               foreign_key: { on_delete: :cascade }
      t.references :partner_inbox, null: false, foreign_key: { to_table: :inboxes, on_delete: :cascade }
      # Kept as audit/redirect even after the strictly technical contact is removed.
      t.bigint :provisional_contact_id
      t.bigint :resolved_contact_id
      t.jsonb :provisional_snapshot, null: false, default: {}
      t.string :state, null: false, default: 'pending'
      t.string :reason, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :last_attempt_at
      t.timestamps
    end
    add_index :whatsapp_identity_resolutions, [:state, :next_attempt_at], name: 'idx_wa_resolution_due'
  end
end
