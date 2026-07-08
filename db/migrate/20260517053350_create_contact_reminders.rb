class CreateContactReminders < ActiveRecord::Migration[7.0]
  def change
    create_table :contact_reminders do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :conversation, foreign_key: true
      t.datetime :scheduled_at, null: false
      t.boolean :send_message, default: false
      t.text :message_content
      t.boolean :is_completed, default: false

      t.timestamps
    end
  end
end
