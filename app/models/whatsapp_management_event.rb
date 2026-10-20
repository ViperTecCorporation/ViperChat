class WhatsappManagementEvent < ApplicationRecord
  RETENTION = 7.days
  MAX_PAYLOAD_BYTES = 256 * 1024
  STATES = %w[recorded processed pending_import review].freeze
  COUNT_KEYS = %w[
    current_limit max_daily_conversations_per_business max_daily_conversation_per_phone
    max_phone_numbers_per_business max_phone_numbers_per_waba contacts_count messages_count
    count total_count progress history_count threads_count kept_messages_count dropped_messages_count invalid_messages_count
    imported_messages_count duplicate_messages_count pending_messages_count failed_messages_count
  ].freeze
  STATUS_KEYS = %w[value status event quality_rating current_quality_rating previous_quality_rating name_status messaging_limit_tier].freeze
  TIER_KEYS = %w[current_limit max_daily_conversations_per_business messaging_limit_tier].freeze
  SAFE_STATUSES = %w[
    GREEN YELLOW RED UNKNOWN HIGH MEDIUM LOW APPROVED REJECTED PENDING AVAILABLE UNAVAILABLE
    CONNECTED DISCONNECTED FLAGGED RESTRICTED DISABLED ENABLED ACTIVE INACTIVE VERIFIED UNVERIFIED
    PENDING_REVIEW IN_REVIEW PAUSED BLOCKED DELETED UPDATED UNLIMITED TIER_250 TIER_1K TIER_2K TIER_10K TIER_100K TIER_UNLIMITED
  ].freeze
  REASONS = %w[
    user_choice_required unknown_field history_ignored unsupported_history_format payload_expired payload_too_large reauthorization_required
    automatic_import_pending import_identity_pending import_failed unsupported_history_message
  ].freeze

  belongs_to :account
  belongs_to :channel, class_name: 'Channel::Whatsapp'
  belongs_to :inbox, optional: true

  validates :field, :digest, :expires_at, presence: true
  validates :digest, format: { with: /\A[0-9a-f]{64}\z/ }, uniqueness: { scope: [:account_id, :channel_id, :field] }
  validates :state, inclusion: { in: STATES }
  validates :reason, inclusion: { in: REASONS }, allow_nil: true
  validate :matching_scope
  validate :bounded_payload

  scope :expired, -> { where(expires_at: ..Time.current) }

  after_create_commit :enqueue_history_import

  def enqueue_history_import
    Whatsapp::ImportHistoryJob.perform_later(id) if field == 'history' && state == 'pending_import'
  end

  # Re-filter at the read boundary: the health response must never expose raw payload or arbitrary strings.
  def summary
    result = { id: id, field: field, state: state, received_at: created_at, details: self.class.snapshot_details(details) }
    result[:reason] = reason if REASONS.include?(reason)
    result
  end

  def self.snapshot_details(value)
    return {} unless value.is_a?(Hash)

    value.stringify_keys.each_with_object({}) do |(key, item), result|
      result[key] = item if safe_snapshot_item?(key, item)
    end
  end

  def self.safe_snapshot_item?(key, item)
    safe_count?(key, item) || safe_tier?(key, item) || (STATUS_KEYS.include?(key) && SAFE_STATUSES.include?(item.to_s))
  end

  def self.safe_count?(key, item)
    COUNT_KEYS.include?(key) && (item.is_a?(Numeric) || item.to_s.match?(/\A\d{1,18}\z/))
  end

  def self.safe_tier?(key, item)
    TIER_KEYS.include?(key) && item.to_s.match?(/\ATIER_(?:250|1K|2K|10K|100K|UNLIMITED)\z/)
  end

  private_class_method :safe_snapshot_item?, :safe_count?, :safe_tier?

  private

  def matching_scope
    errors.add(:channel, 'must belong to the account') if channel && channel.account_id != account_id
    return unless inbox
    return if inbox.account_id == account_id && inbox.channel == channel

    errors.add(:inbox, 'must belong to the channel and account')
  end

  def bounded_payload
    errors.add(:payload, 'exceeds retention size limit') if payload.to_json.bytesize > MAX_PAYLOAD_BYTES
  end
end
