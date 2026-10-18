# Initial sync is a one-time operation: callers must never automatically retry errors.
class Whatsapp::SmbAppDataClient
  SYNC_TYPES = %w[smb_app_state_sync history].freeze

  class Error < StandardError
    attr_reader :reason

    def initialize(reason, ambiguous:)
      @reason = reason
      @ambiguous = ambiguous
      super('WhatsApp initial sync request could not be confirmed')
    end

    def ambiguous?
      @ambiguous
    end
  end

  def initialize(channel)
    @provider = channel.provider.deep_dup
    @config = channel.provider_config.deep_dup
  end

  def request(sync_type)
    dispatched = false
    raise Error.new('invalid_sync_type', ambiguous: false) unless SYNC_TYPES.include?(sync_type)

    version = Whatsapp::ApiVersion.current
    validate_configuration!(version)

    dispatched = true
    parse_response(post_request(sync_type, version))
  rescue Error
    raise
  rescue JSON::ParserError
    raise Error.new('invalid_response', ambiguous: dispatched), cause: nil
  rescue StandardError
    reason = dispatched ? 'temporarily_unavailable' : 'configuration_missing'
    raise Error.new(reason, ambiguous: dispatched), cause: nil
  end

  private

  def post_request(sync_type, version)
    HTTParty.post(
      "https://graph.facebook.com/#{version}/#{@config['phone_number_id']}/smb_app_data",
      headers: { 'Authorization' => "Bearer #{@config['api_key']}", 'Content-Type' => 'application/json' },
      body: { messaging_product: 'whatsapp', sync_type: sync_type }.to_json,
      timeout: 10,
      follow_redirects: false
    )
  end

  def parse_response(response)
    raise Error.new('http_error', ambiguous: true) unless response.success?

    body = JSON.parse(response.body)
    request_id = body['request_id'] if body.is_a?(Hash) && !body.key?('error')
    raise Error.new('invalid_response', ambiguous: true) unless valid_request_id?(request_id)

    request_id
  end

  def valid_request_id?(request_id)
    request_id.is_a?(String) && request_id.bytesize <= 255 && /\A[^\s[:cntrl:]]+\z/.match?(request_id)
  end

  def validate_configuration!(version)
    valid = @provider == 'whatsapp_cloud' && @config.is_a?(Hash) &&
            valid_string?(@config['phone_number_id'], /\A\d+\z/) &&
            valid_string?(@config['api_key'], /\A[\x21-\x7e]+\z/) && valid_string?(version, /\Av\d+\.0\z/)
    raise Error.new('configuration_missing', ambiguous: false) unless valid
  end

  def valid_string?(value, pattern)
    value.is_a?(String) && pattern.match?(value)
  end
end
