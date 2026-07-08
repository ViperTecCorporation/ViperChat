class AddDescriptionToContactReminders < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:contact_reminders, :description)
      add_column :contact_reminders, :description, :text
    end
  end
end
