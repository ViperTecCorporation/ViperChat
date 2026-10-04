class AddUnoWebAttendance < ActiveRecord::Migration[7.1]
  def change
    change_table :inboxes, bulk: true do |t|
      t.boolean :web_attendance_enabled, default: false, null: false
      t.boolean :web_attendance_greeting_enabled, default: false, null: false
      t.string :web_attendance_button_text, default: 'Continuar atendimento', null: false
    end
    change_table :conversations, bulk: true do |t|
      t.integer :web_attendance_cycle, default: 1, null: false
      t.datetime :web_attendance_started_at, :web_attendance_greeting_sent_at, :web_agent_last_seen_at, :channel_agent_last_seen_at
    end
    add_column :messages, :delivery_destination, :string, default: 'channel', null: false
    add_index :messages, [:conversation_id, :delivery_destination, :created_at], name: 'index_messages_on_destination_and_conversation'

    create_invitations
    create_sessions
  end

  private

  def create_invitations
    create_table :web_attendance_invitations do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :message, foreign_key: true
      t.string :token_digest, null: false
      t.text :encrypted_token, null: false
      t.integer :cycle, null: false
      t.datetime :activated_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :web_attendance_invitations, :token_digest, unique: true
  end

  def create_sessions
    create_table :web_attendance_sessions do |t|
      t.references :web_attendance_invitation, null: false, foreign_key: true, index: { name: 'index_web_sessions_on_invitation' }
      t.string :token_digest, null: false
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :web_attendance_sessions, :token_digest, unique: true
  end
end
