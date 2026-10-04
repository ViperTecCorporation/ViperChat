class BindWebAttendanceInvitationIdentity < ActiveRecord::Migration[7.1]
  def change
    add_reference :web_attendance_invitations, :account, foreign_key: true
    add_reference :web_attendance_invitations, :inbox, foreign_key: true
    add_reference :web_attendance_invitations, :contact, foreign_key: true
  end
end
