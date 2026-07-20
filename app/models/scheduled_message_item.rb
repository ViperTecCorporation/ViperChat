class ScheduledMessageItem < ApplicationRecord
  belongs_to :scheduled_message
  belongs_to :message, optional: true

  has_many_attached :files

  enum status: { pending: 0, dispatching: 1, sent: 2, failed: 3, cancelled: 4 }

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 5 }
  validates :content_type, presence: true
  validate :content_or_attachment

  def signed_attachment_ids
    return files.map { |attachment| attachment.blob.signed_id } if files.attached?

    attachment_blob_ids
  end

  private

  def content_or_attachment
    return if content.present? || attachment_blob_ids.present? || files.attached?

    errors.add(:base, 'message must have content or an attachment')
  end
end
