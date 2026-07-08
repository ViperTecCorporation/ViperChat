class ContactReminder < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :user, optional: true
  belongs_to :conversation, optional: true

  validates :scheduled_at, presence: true
  validates :message_content, presence: true, if: :send_message?

  scope :pending, -> { where(is_completed: false) }
  scope :due, -> { where('scheduled_at <= ?', Time.current) }
end
