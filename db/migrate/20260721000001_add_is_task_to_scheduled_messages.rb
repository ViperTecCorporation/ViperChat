class AddIsTaskToScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :scheduled_messages, :is_task, :boolean, default: false, null: false
  end
end
