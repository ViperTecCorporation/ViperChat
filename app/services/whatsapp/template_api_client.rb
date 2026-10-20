# Shared transport for template administration. No raw Graph errors or credentials leave this client.
class Whatsapp::TemplateApiClient
  def initialize(waba_id:, token:)
    @url = "https://graph.facebook.com/#{Whatsapp::ApiVersion.current}/#{waba_id}/message_templates"
    @token = token
  end

  def create(payload)
    request(:post, body: payload.to_json)
  end

  def list(cursor)
    request(:get, query: { limit: 100, after: cursor }.compact)
  end

  private

  def request(method, options)
    response = HTTParty.public_send(method, @url, **options,
                                   headers: { 'Authorization' => "Bearer #{@token}", 'Content-Type' => 'application/json' },
                                   timeout: 15, no_follow: true)
    data = response.parsed_response
    return { error: unknown_reason(method) } unless data.is_a?(Hash)
    return data if response.success? && data['error'].blank?

    failure(response.code.to_i, data['error'], method)
  rescue StandardError
    { error: unknown_reason(method) }
  end

  def failure(status, error, method)
    error = {} unless error.is_a?(Hash)
    code = error['code']
    reason = if code == 190
               'authentication_required'
             elsif [10, 200].include?(code)
               'permission_denied'
             elsif status >= 500 || status < 400
               unknown_reason(method)
             else
               'provider_rejected'
             end
    { error: reason, provider_code: code, provider_subcode: error['error_subcode'],
      provider_message: safe_message(error['error_user_msg']) }.compact
  end

  def safe_message(message)
    return unless message.is_a?(String)

    message.gsub(@token, '[redacted]').gsub(/access_token\s*[=:]\s*[^\s&]+/i, 'access_token=[redacted]').truncate(500)
  end

  def unknown_reason(method)
    method == :post ? 'outcome_unknown' : 'temporarily_unavailable'
  end
end
