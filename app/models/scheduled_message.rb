class ScheduledMessage < ApplicationRecord
  MAX_ITEMS = 5

  belongs_to :account
  belongs_to :conversation
  belongs_to :target_conversation, class_name: 'Conversation', optional: true
  belongs_to :contact
  belongs_to :inbox
  belongs_to :label, optional: true
  belongs_to :created_by, class_name: 'User'
  belongs_to :sender, class_name: 'User'
  belongs_to :message, optional: true
  has_many :items, -> { order(:position) }, class_name: 'ScheduledMessageItem', dependent: :destroy, inverse_of: :scheduled_message

  enum status: { scheduled: 0, sending: 1, sent: 2, failed: 3, cancelled: 4 }

  validates :scheduled_at, presence: true
  validate :scheduled_at_must_be_in_the_future, if: :scheduled?
  validate :account_consistency
  validate :items_count_within_limit, unless: :is_task?
  validates_associated :items, unless: :is_task?

  scope :due, -> { scheduled.where(scheduled_at: ..Time.current) }
  scope :due_tasks, -> { scheduled.where(is_task: true, scheduled_at: ..Time.current) }
  scope :due_messages, -> { scheduled.where(is_task: false, scheduled_at: ..Time.current) }

  def ensure_legacy_item!
    return if items.exists?

    items.create!(
      position: 0,
      content: content,
      content_type: content_type.presence || 'text',
      content_attributes: content_attributes,
      attachment_blob_ids: attachment_blob_ids,
      status: sent? ? :sent : :pending,
      message: message,
      sent_at: sent_at
    )
  end

  private

  def scheduled_at_must_be_in_the_future
    errors.add(:scheduled_at, 'must be in the future') if scheduled_at && scheduled_at <= Time.current
  end

  def account_consistency
    records = [conversation, contact, inbox, label].compact
    errors.add(:base, 'all records must belong to the account') if records.any? { |record| record.account_id != account_id }
    validate_account_user(:sender, sender_id)
    validate_account_user(:created_by, created_by_id)
  end

  def validate_account_user(attribute, user_id)
    errors.add(attribute, 'must belong to the account') unless account&.users&.exists?(id: user_id)
  end

  def items_count_within_limit
    return if items.empty? || items.size.between?(1, MAX_ITEMS)

    errors.add(:items, "must contain between 1 and #{MAX_ITEMS} messages")
  end
end
