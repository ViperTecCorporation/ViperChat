class AddWebAttendanceInvitationMessage < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :web_attendance_invitation_message, :text, null: false, default: ''
  end
end
