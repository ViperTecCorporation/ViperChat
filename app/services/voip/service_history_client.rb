class Voip::ServiceHistoryClient
  MAX_BYTES = 2.megabytes
  MAX_CURSOR_BYTES = 2048
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
  HTTP_ERRORS = {
    400 => :InvalidCursorError, 401 => :AuthenticationError, 403 => :AuthenticationError,
    409 => :ScopeChangedError, 410 => :CursorExpiredError, 501 => :UnsupportedError
  }.freeze

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ResponseError < Error; end
  class ConnectionError < Error; end
  class InvalidCursorError < Error; end
  class AuthenticationError < Error; end
  class ScopeChangedError < Error; end
  class CursorExpiredError < Error; end
  class UnsupportedError < Error; end

  def initialize(service)
    @credentials = service.credentials
  end

  # Explicit, read-only invocation. Never originates SIP calls or mutates local call records.
  def fetch_changes(cursor: nil, limit: 100, session_scope: nil)
    validate_arguments!(cursor, limit)
    options = request_options(cursor, limit)
    add_scope!(options, session_scope) unless session_scope.nil?
    validate_payload!(JSON.parse(read_response(options, session_scope)), limit)
  rescue JSON::ParserError, EncodingError
    raise ResponseError, 'Invalid history JSON', cause: nil
  rescue SafeFetch::Error, SsrfFilter::Error, Resolv::ResolvError, URI::InvalidURIError,
         Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError, IOError, SystemCallError
    # Lower-level errors can include the URL, cursor, or headers; do not expose their messages or causes.
    raise ConnectionError, 'History connection failed or destination blocked', cause: nil
  end

  private

  attr_reader :credentials

  def add_scope!(options, scope)
    valid = scope.is_a?(Array) && scope.size <= 1000 && scope.all? { |line| line.is_a?(String) && line.match?(/\A\d{8,15}\z/) }
    raise ConfigurationError, 'Invalid history line scope' unless valid

    options.headers['X-Unoapi-Session-Scope'] = scope.uniq.sort.to_json
  end

  def read_response(options, session_scope)
    body = +''
    perform_request(options) do |response|
      validate_http_response!(response)
      if !session_scope.nil? && response['x-unoapi-session-scope-applied'] != '1'
        raise ScopeChangedError, 'History service did not confirm line isolation'
      end

      response.read_body do |chunk|
        raise ResponseError, 'History response exceeds size limit' if body.bytesize + chunk.bytesize > MAX_BYTES

        body << chunk
      end
    end
    body
  end

  def validate_arguments!(cursor, limit)
    raise InvalidCursorError, 'Invalid history cursor' unless cursor.nil? || valid_cursor?(cursor)
    raise ArgumentError, 'History limit must be between 1 and 100' unless limit.is_a?(Integer) && limit.between?(1, 100)
  end

  def valid_cursor?(value)
    value.is_a?(String) && value.present? && value.bytesize <= MAX_CURSOR_BYTES
  end

  def request_options(cursor, limit)
    uri = configured_uri!
    uri.path = "#{uri.path.delete_suffix('/')}/v1/console/history"
    uri.query = URI.encode_www_form({ sync: 'changes', limit: limit }.merge(cursor ? { cursor: cursor } : {}))
    SafeFetch::RequestOptions.new(
      url: uri.to_s, open_timeout: 3, read_timeout: 10,
      headers: { 'Authorization' => "Bearer #{credentials['history_api_token']}", 'Accept' => 'application/json' }
    )
  end

  def configured_uri!
    uri = URI.parse(credentials['history_api_url'].to_s)
    raise ConfigurationError, 'Invalid service history configuration' unless valid_credentials? && valid_base_uri?(uri) && secure_scheme?(uri)

    uri
  rescue URI::InvalidURIError
    raise ConfigurationError, 'Invalid service history configuration', cause: nil
  end

  def valid_credentials?
    token = credentials['history_api_token']
    credentials['integration_provider'] == 'viperconnect' && token.is_a?(String) && token.present? && !token.match?(/[\r\n]/)
  end

  def valid_base_uri?(uri)
    uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
  end

  def secure_scheme?(uri)
    uri.scheme == 'https' || (!Rails.env.production? && LOOPBACK_HOSTS.include?(uri.hostname))
  end

  def perform_request(options, &)
    # Preserve the application's explicit private-network policy; redirects are rejected in the response block.
    return SafeFetch::PrivateNetworkRequest.new(options).perform(&) if SafeFetch.allow_private_network? || trusted_origin?(options.url)

    SsrfFilter.get(options.url, **options.request_options, max_redirects: 0, &)
  end

  def trusted_origin?(url)
    origins = ENV.fetch('VOIP_TRUSTED_SERVICE_ORIGINS', '').split(',').map(&:strip).reject(&:empty?)
    origins = origins.map { |origin| trusted_origin_tuple(origin) }
    requested = URI.parse(url)
    origins.include?([requested.scheme, requested.hostname.downcase, requested.port])
  rescue URI::InvalidURIError
    raise ConfigurationError, 'Invalid trusted VoIP service origin', cause: nil
  end

  def trusted_origin_tuple(origin)
    uri = URI.parse(origin)
    valid = valid_base_uri?(uri) && uri.scheme == 'https' && ['', '/'].include?(uri.path)
    raise ConfigurationError, 'Invalid trusted VoIP service origin' unless valid

    [uri.scheme, uri.hostname.downcase, uri.port]
  end

  def validate_http_response!(response)
    code = response.code.to_i
    error = HTTP_ERRORS[code]
    raise self.class.const_get(error), "History request rejected (#{code})" if error
    raise ResponseError, "Unexpected history HTTP status (#{code})" unless code == 200

    content_type = response['content-type'].to_s.split(';').first.to_s.strip.downcase
    raise ResponseError, 'History response must be JSON' unless content_type == 'application/json'
    raise ResponseError, 'History response exceeds size limit' if response['content-length'].to_i > MAX_BYTES
  end

  def validate_payload!(payload, limit)
    valid = valid_envelope?(payload) && payload['items'].is_a?(Array) && payload['items'].size <= limit
    raise ResponseError, 'Invalid history envelope' unless valid
    raise ResponseError, 'Invalid history records' unless payload['items'].all? { |item| valid_item?(item) }

    payload
  end

  def valid_envelope?(payload)
    payload.is_a?(Hash) && payload['version'].is_a?(Integer) && payload['version'] == 1 &&
      %w[snapshot changes].include?(payload['phase']) && valid_cursor?(payload['nextCursor']) && [true, false].include?(payload['hasMore'])
  end

  def valid_item?(item)
    return false unless item.is_a?(Hash) && item['sequence'].is_a?(Integer) && item['sequence'].positive?

    valid_record?(item['record'])
  end

  def valid_record?(record)
    return false unless record.is_a?(Hash) && %w[id callId direction status startedAt].all? do |key|
      record[key].is_a?(String) && record[key].present?
    end

    %w[inbound outbound internal].include?(record['direction']) &&
      %w[routing ringing active completed missed failed cancelled].include?(record['status']) && valid_timestamp?(record['startedAt'])
  end

  def valid_timestamp?(value)
    Time.iso8601(value)
    true
  rescue ArgumentError
    false
  end
end
