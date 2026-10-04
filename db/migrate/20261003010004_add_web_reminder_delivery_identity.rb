class AddWebReminderDeliveryIdentity < ActiveRecord::Migration[7.1]
  def change
    remove_index :messages, "(content_attributes->>'web_absence_request_key')",
                 name: 'index_messages_on_web_absence_request_key', unique: true,
                 where: "content_attributes->>'web_absence_request_key' IS NOT NULL"
    change_table :messages, bulk: true do |t|
      t.string :web_absence_request_key
      t.datetime :web_reminder_attempted_at
    end
    add_index :messages, :web_absence_request_key, unique: true, where: 'web_absence_request_key IS NOT NULL'
  end
end
