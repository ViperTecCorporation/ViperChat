# Read-only management calls. Tokens and raw Graph errors never leave this client.
class Whatsapp::ManagementApiClient
  class Error < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super('WhatsApp management data is unavailable')
    end
  end

  def initialize(channel)
    @channel = channel
    @version = Whatsapp::ApiVersion.current
  end

  def get(node_id, fields:)
    validate_configuration!(node_id)

    response = HTTParty.get("https://graph.facebook.com/#{@version}/#{node_id}",
                            headers: { 'Authorization' => "Bearer #{token}" }, query: { fields: fields }, timeout: 5)
    body = response.parsed_response
    raise Error, 'invalid_response' unless body.is_a?(Hash)
    raise Error, error_reason(body.dig('error', 'code')) unless response.success? && body['error'].blank?

    body
  rescue Error
    raise
  rescue StandardError
    raise Error, 'temporarily_unavailable'
  end

  private

  def validate_configuration!(node_id)
    raise Error, 'configuration_missing' unless @channel.provider == 'whatsapp_cloud' && node_id.present? && token.present?
  end

  def token
    @channel.provider_config['api_key']
  end

  def error_reason(code)
    return 'permission_denied' if [10, 190, 200].include?(code)
    return 'unsupported' if code == 100

    'temporarily_unavailable'
  end
end
