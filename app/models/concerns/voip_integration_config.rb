module VoipIntegrationConfig
  extend ActiveSupport::Concern

  INTEGRATION_FIELDS = %w[integration_provider webhook_source_instance_id history_api_url history_company_id].freeze
  SECRET_FIELDS = %w[history_api_token].freeze
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

  included do
    validate :valid_integration_config
  end

  def integration_provider
    credentials.fetch('integration_provider', 'none')
  end

  def integration_payload
    credentials.slice(*INTEGRATION_FIELDS).reverse_merge('integration_provider' => 'none').merge(
      SECRET_FIELDS.index_with { |field| credentials[field].present? }.transform_keys { |field| "#{field}_configured" }
    )
  end

  private

  def valid_integration_config
    values = credentials
    unless %w[none webhook viperconnect].include?(integration_provider)
      errors.add(:integration_provider, 'is invalid')
      return
    end

    validate_integration_secret(:webhook_source_instance_id, values['webhook_source_instance_id'], 200) if integration_provider != 'none'
    validate_history_config(values)
    validate_integration_secret(:history_company_id, values['history_company_id'], 200) if values['history_company_id'].present?
  end

  def validate_history_config(values)
    required = integration_provider == 'viperconnect'
    url = values['history_api_url']
    validate_history_url(url) if required || url.present?
    token = values['history_api_token']
    validate_integration_secret(:history_api_token, token, 4096) if required || token.present?
  end

  def validate_history_url(url)
    uri = URI.parse(url.to_s)
    secure = secure_history_scheme?(uri)
    valid = secure && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
    errors.add(:history_api_url, 'must use HTTPS without credentials, query or fragment') unless valid
  rescue URI::InvalidURIError
    errors.add(:history_api_url, 'is invalid')
  end

  def validate_integration_secret(field, value, maximum)
    valid = value.is_a?(String) && value.present? && value.length <= maximum && !value.match?(/[\x00-\x1f\x7f]/)
    errors.add(field, 'must be a non-empty string without control characters') unless valid
  end

  def development_loopback?(host)
    !Rails.env.production? && LOOPBACK_HOSTS.include?(host)
  end

  def secure_history_scheme?(uri)
    uri.scheme == 'https' || (uri.scheme == 'http' && development_loopback?(uri.hostname))
  end
end
