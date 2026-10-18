class Whatsapp::HealthService
  def initialize(channel)
    @channel = channel
    @access_token = channel.provider_config['api_key']
    @client = Whatsapp::ManagementApiClient.new(channel)
  end

  def fetch_health_status
    validate_channel!
    fetch_phone_health_data
  end

  private

  def validate_channel!
    raise ArgumentError, 'Channel is required' if @channel.blank?
    raise ArgumentError, 'API key is missing' if @access_token.blank?
    raise ArgumentError, 'Phone number ID is missing' if @channel.provider_config['phone_number_id'].blank?
  end

  def fetch_phone_health_data
    phone_number_id = @channel.provider_config['phone_number_id']

    response = @client.get(phone_number_id, fields: health_fields)
    format_health_response(response).merge(fetch_messaging_limit, fetched_at: Time.current.iso8601)
  end

  def health_fields
    %w[
      id
      quality_rating
      code_verification_status
      account_mode
      display_phone_number
      name_status
      verified_name
      webhook_configuration
      throughput
      last_onboarded_time
      platform_type
      certificate
    ].join(',')
  end

  def fetch_messaging_limit
    data = @client.get(@channel.provider_config['business_account_id'], fields: 'whatsapp_business_manager_messaging_limit')
    tier = data['whatsapp_business_manager_messaging_limit'].presence
    { messaging_limit_tier: tier, whatsapp_business_manager_messaging_limit: tier,
      messaging_limit_scope: tier ? 'business_portfolio' : 'unknown', limit_source: 'whatsapp_business_manager_messaging_limit' }
  rescue Whatsapp::ManagementApiClient::Error
    { messaging_limit_tier: nil, whatsapp_business_manager_messaging_limit: nil, messaging_limit_scope: 'unknown', limit_source: nil }
  end

  def format_health_response(response)
    {
      id: response['id'],
      display_phone_number: response['display_phone_number'],
      verified_name: response['verified_name'],
      name_status: response['name_status'],
      quality_rating: response['quality_rating'],
      account_mode: response['account_mode'],
      code_verification_status: response['code_verification_status'],
      webhook_configuration: response['webhook_configuration'],
      expected_webhook_url: build_expected_webhook_url,
      throughput: response['throughput'],
      last_onboarded_time: response['last_onboarded_time'],
      platform_type: response['platform_type'],
      certificate: response['certificate'],
      business_id: @channel.provider_config['business_account_id']
    }
  end

  def build_expected_webhook_url
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    return nil if frontend_url.blank?

    "#{frontend_url}/webhooks/whatsapp/#{@channel.phone_number}"
  end
end
