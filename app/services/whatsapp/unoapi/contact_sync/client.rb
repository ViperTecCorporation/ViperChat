require 'uri'

class Whatsapp::Unoapi::ContactSync::Client
  class Error < StandardError; end
  class TransientError < Error; end
  class PermanentError < Error; end
  class ProviderMismatchError < PermanentError; end

  def initialize(channel)
    @channel = channel
  end

  def session_online?
    response = request("#{base_url}/sessions")
    raise_for_response!(response)
    raise PermanentError, 'UnoAPI sessions response is not an object' unless response.parsed_response.is_a?(Hash)

    session = Array(response.parsed_response['data']).find do |item|
      session_identifiers(item).intersect?(channel_identifiers)
    end

    session&.fetch('status', nil) == 'online'
  end

  def contacts(cursor:)
    query = URI.encode_www_form(cursor: cursor, limit: 200)
    response = request("#{base_url}/#{session_id}/contacts?#{query}")
    raise_for_response!(response)

    response.parsed_response
  end

  def verify_contact(phone_number)
    response = request(
      "#{base_url}/#{session_id}/contacts",
      method: :post,
      body: { contacts: [phone_number] }.to_json
    )
    raise_for_response!(response)
    contact = response.parsed_response&.fetch('contacts', nil)&.first
    raise PermanentError, 'UnoAPI contact verification response is invalid' unless contact.is_a?(Hash)

    contact
  end

  def import_contact(payload)
    response = request(
      "#{base_url}/#{session_id}/contacts/import",
      method: :post,
      body: payload.to_json
    )
    raise_for_response!(response, transient_codes: [409])
    parsed_response = response.parsed_response
    valid_response = parsed_response.is_a?(Hash) && parsed_response['success'] == true && parsed_response['contact'].is_a?(Hash)
    raise PermanentError, 'UnoAPI contact import response is invalid' unless valid_response

    parsed_response
  end

  private

  def request(url, method: :get, body: nil)
    HTTParty.public_send(method, url, headers: headers, timeout: 30, body: body)
  rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => e
    raise TransientError, "#{e.class}: #{e.message}"
  end

  def raise_for_response!(response, transient_codes: [])
    return if response.success?

    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : response.body
    raise ProviderMismatchError, error if response.code == 409 && error == 'contact_directory_requires_zapo_provider'

    raise TransientError, "UnoAPI HTTP #{response.code}: #{error}" if transient_response?(response, transient_codes)

    raise PermanentError, "UnoAPI HTTP #{response.code}: #{error}"
  end

  def transient_response?(response, transient_codes)
    transient_codes.include?(response.code) || response.code == 429 || response.code >= 500
  end

  def base_url
    @channel.provider_config.fetch('url').delete_suffix('/')
  end

  def headers
    {
      'Authorization' => ENV.fetch('UNOAPI_AUTH_TOKEN', @channel.provider_config.fetch('api_key')),
      'Content-Type' => 'application/json'
    }
  end

  def session_id
    @channel.provider_config['phone_number_id'].presence ||
      @channel.provider_config['business_account_id'].presence ||
      @channel.phone_number.delete('+')
  end

  def channel_identifiers
    @channel_identifiers ||= [
      @channel.phone_number,
      @channel.provider_config['phone_number_id'],
      @channel.provider_config['business_account_id']
    ].compact_blank.map { |value| normalize_identifier(value) }.uniq
  end

  def session_identifiers(session)
    session.values_at('phone', 'id', 'display_phone_number').compact_blank.map { |value| normalize_identifier(value) }.uniq
  end

  def normalize_identifier(value)
    value.to_s.gsub(/\D/, '')
  end
end
