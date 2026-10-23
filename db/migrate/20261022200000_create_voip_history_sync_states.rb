class CreateVoipHistorySyncStates < ActiveRecord::Migration[7.1]
  def change
    create_table :voip_history_sync_states do |t|
      t.references :voip_service, null: false, foreign_key: true, index: { unique: true }
      t.string :state, null: false, default: 'pending'
      t.text :encrypted_cursor
      t.string :scope_digest
      t.string :lease_token
      t.datetime :lease_expires_at
      t.datetime :last_attempt_at
      t.datetime :last_success_at
      t.string :last_error_code
      t.datetime :next_attempt_at
      t.boolean :has_more, null: false, default: false
      t.boolean :gap_detected, null: false, default: false
      t.boolean :reset_requested, null: false, default: false
      t.integer :failures, null: false, default: 0
      request_audit(t)
      t.timestamps
    end
    add_index :voip_history_sync_states, [:state, :next_attempt_at]
  end

  def request_audit(table)
    table.datetime :last_requested_at
    table.bigint :last_requested_by_id
    table.datetime :last_reset_at
  end
end
