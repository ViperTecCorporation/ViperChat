class WhatsappSticker < ApplicationRecord
  include Rails.application.routes.url_helpers

  ACCEPTED_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :blob, class_name: 'ActiveStorage::Blob'

  validates :account_id, :inbox_id, :blob_id, presence: true
  validates :blob_id, uniqueness: { scope: :inbox_id }
  validate :validate_blob_content_type

  def file_url
    ensure_url_options
    url_for(blob)
  end

  def thumb_url
    ensure_url_options
    return file_url unless blob.image?

    url_for(blob.variant(resize_to_limit: [200, 200]))
  rescue ActiveStorage::InvariableError, ActiveStorage::UnrepresentableError
    file_url
  end

  private

  def ensure_url_options
    return if ActiveStorage::Current.url_options.present?

    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options.presence
    return if ActiveStorage::Current.url_options.present?

    host = ENV.fetch('FRONTEND_URL', nil)
    ActiveStorage::Current.url_options = { host: host } if host.present?
  end

  def validate_blob_content_type
    return if blob&.content_type.in?(ACCEPTED_CONTENT_TYPES)

    errors.add(:blob_id, 'type not supported')
  end
end
