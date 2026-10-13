class AddWebAttendancePresence < ActiveRecord::Migration[7.1]
  def change
    change_table :web_attendance_sessions, bulk: true do |t|
      t.datetime :presence_seen_at
      t.boolean :visible, default: false, null: false
      t.jsonb :presence_entries, default: {}, null: false
    end
    change_table :conversations, bulk: true do |t|
      t.boolean :web_presence_online, default: false, null: false
      t.datetime :web_absent_since
      t.bigint :web_absence_epoch, default: 0, null: false
      t.bigint :web_reminded_epoch
      t.bigint :web_reminder_pending_message_id
    end
    add_index :messages, "(content_attributes->>'web_absence_request_key')",
              unique: true, where: "content_attributes->>'web_absence_request_key' IS NOT NULL",
              name: 'index_messages_on_web_absence_request_key'
  end
end
