class WebAttendanceSession < ApplicationRecord
  belongs_to :web_attendance_invitation
  delegate :conversation, to: :web_attendance_invitation
  validates :token_digest, presence: true, uniqueness: true
  validates :visible, inclusion: { in: [true, false] }

  def active?
    web_attendance_invitation.active?
  end

  def visible_presence?(now = Time.current)
    presence_entries.values.any? { |entry| entry['visible'] == true && entry['seen_at'].to_f >= (now - 10.seconds).to_f }
  end
end
