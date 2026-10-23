class VoipService < ApplicationRecord
  include VoipCredentials
  include VoipIntegrationConfig
  belongs_to :account
  has_many :voip_agent_extensions, dependent: :destroy
  has_many :voip_favorites, dependent: :destroy
  has_one :history_sync_state, class_name: 'VoipHistorySyncState', dependent: :restrict_with_exception

  validates :name, presence: true, length: { maximum: 100 }
  validates :sip_domain, format: { with: /\A[a-zA-Z0-9.-]+(?::[0-9]{1,5})?\z/ }
  validate :secure_websocket
  validates :registration_expires, numericality: { only_integer: true, greater_than_or_equal_to: 60, less_than_or_equal_to: 3600 }
  validate :authorized_users

  def available_to?(membership)
    membership.account_id == account_id && enabled? &&
      (membership.administrator? || allowed_user_ids.empty? || allowed_user_ids.include?(membership.user_id))
  end

  def public_payload
    slice(:id, :name, :enabled, :allow_self_configuration, :transfer_enabled, :registration_expires, :updated_at).merge(
      credential_configured: credentials.present?
    )
  end

  def admin_payload
    public_payload.merge(slice(:wss_url, :sip_domain, :allowed_user_ids)).merge(integration_payload).merge(
      stun_url: credentials['stun_url'], turn_url: credentials['turn_url'], turn_username: credentials['turn_username']
    )
  end

  def ice_servers
    values = credentials
    servers = []
    servers << { urls: values['stun_url'] } if values['stun_url'].present?
    servers << { urls: values['turn_url'], username: values['turn_username'], credential: values['turn_password'] } if values['turn_url'].present?
    servers
  end

  def history_sync_payload
    defaults = { cursor_configured: false, has_more: false, gap_detected: false }
    return defaults.merge(state: 'unsupported') unless integration_provider == 'viperconnect'
    return defaults.merge(state: 'configuration_required') if credentials['history_company_id'].blank?

    checkpoint = history_sync_state
    return defaults.merge(state: 'pending') unless checkpoint
    return checkpoint.public_payload if checkpoint.scope_digest == Voip::SyncHistoryService.configuration_digest(self)

    checkpoint.public_payload.merge('state' => 'pending')
  end

  private

  def authorized_users
    return if account.blank?

    # Removed members must not block editing a service or turn its restricted allowlist into public access.
    previous = allowed_user_ids_in_database || []
    return if allowed_user_ids.is_a?(Array) && (allowed_user_ids - previous - account.account_users.pluck(:user_id)).empty?

    errors.add(:allowed_user_ids, 'must belong to this account')
  end

  def secure_websocket
    uri = URI.parse(wss_url.to_s)
    valid = secure_scheme?(uri) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
    errors.add(:wss_url, 'must use WSS (loopback WS is allowed only in development)') unless valid
  rescue URI::InvalidURIError
    errors.add(:wss_url, 'is invalid')
  end

  def secure_scheme?(uri)
    uri.scheme == 'wss' || (!Rails.env.production? && uri.scheme == 'ws' && %w[localhost 127.0.0.1 ::1].include?(uri.hostname))
  end
end
