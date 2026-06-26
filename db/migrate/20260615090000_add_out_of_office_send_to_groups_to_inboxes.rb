class AddOutOfOfficeSendToGroupsToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :out_of_office_send_to_groups, :boolean, default: false, null: false
  end
end
