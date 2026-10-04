class AddWebAttendanceHistoryBoundary < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :web_attendance_start_message_id, :bigint
  end
end
