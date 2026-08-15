require 'cgi'

class Whatsapp::Unoapi::ProfilePictureClient
  class Error < StandardError; end
  class NotFoundError < Error; end
  class AuthenticationError < Error; end
  class TransientError < Error; end
  class InvalidResponseError < Error; end

  Result = Data.define(:body, :content_type)

  MAX_DOWNLOAD_SIZE = 15.megabytes

  def initialize(channel)
    @channel = channel
  end

  def fetch(picture_id)
    validate_configuration!(picture_id)
    response = HTTParty.get(endpoint(picture_id), headers: headers, timeout: 30)
    raise_for_response!(response)
    validate_image!(response)

    Result.new(body: response.body, content_type: normalized_content_type(response.headers['content-type']))
  rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => e
    raise TransientError, "#{e.class}: #{e.message}"
  end

  private

  def validate_configuration!(picture_id)
    raise InvalidResponseError, 'UnoAPI picture_id is blank' if picture_id.blank?
    raise InvalidResponseError, 'UnoAPI URL is not configured' if @channel.unoapi_api_url.blank?
    raise AuthenticationError, 'UnoAPI token is not configured' if @channel.unoapi_auth_token.blank?
  end

  def endpoint(picture_id)
    escaped_picture_id = CGI.escape(picture_id.to_s).gsub('+', '%20')
    "#{@channel.unoapi_api_url}/v13.0/#{session_id}/profile-pictures/#{escaped_picture_id}"
  end

  def session_id
    @channel.provider_config['phone_number_id'].presence ||
      @channel.provider_config['business_account_id'].presence ||
      @channel.phone_number.to_s.delete('+')
  end

  def headers
    {
      'Authorization' => @channel.unoapi_auth_token,
      'Accept' => 'image/*'
    }
  end

  def raise_for_response!(response)
    return if response.success?

    raise NotFoundError, 'UnoAPI profile picture not found' if response.code == 404
    raise AuthenticationError, "UnoAPI profile picture HTTP #{response.code}" if [401, 403].include?(response.code)
    raise TransientError, "UnoAPI profile picture HTTP #{response.code}" if response.code == 429 || response.code >= 500

    raise InvalidResponseError, "UnoAPI profile picture HTTP #{response.code}"
  end

  def validate_image!(response)
    content_type = normalized_content_type(response.headers['content-type'])
    unless Avatarable::ALLOWED_AVATAR_CONTENT_TYPES.include?(content_type)
      raise InvalidResponseError, "Unsupported profile picture type: #{content_type}"
    end
    raise InvalidResponseError, 'UnoAPI profile picture exceeds 15 MB' if response.body.to_s.bytesize > MAX_DOWNLOAD_SIZE
  end

  def normalized_content_type(content_type)
    content_type.to_s.split(';').first.to_s.strip.downcase
  end
end
