class VoipHistorySyncState < ApplicationRecord
  self.filter_attributes += [:encrypted_cursor, :lease_token]
  belongs_to :voip_service
  BLOCKED_STATES = %w[configuration_required invalid_cursor scope_changed authentication_failed unsupported revision_conflict].freeze
  validates :state, inclusion: { in: BLOCKED_STATES + %w[pending running caught_up retry] }

  def cursor
    checkpoint_cipher.decrypt_and_verify(encrypted_cursor, purpose: 'voip-history-checkpoint') if encrypted_cursor.present?
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    raise Voip::ServiceHistoryClient::InvalidCursorError, 'Invalid encrypted checkpoint', cause: nil
  end

  def cursor=(value)
    self.encrypted_cursor = value.nil? ? nil : checkpoint_cipher.encrypt_and_sign(value, purpose: 'voip-history-checkpoint')
  end

  def public_payload
    slice(:state, :last_attempt_at, :last_success_at, :last_error_code, :next_attempt_at, :has_more, :gap_detected,
          :last_requested_at, :last_requested_by_id, :last_reset_at).merge(
            cursor_configured: encrypted_cursor.present?
          )
  end

  private

  def checkpoint_cipher
    key = Rails.application.key_generator.generate_key('viperchat-voip-history-checkpoint-v1', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
  end
end
