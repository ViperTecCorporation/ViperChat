class Voip::WebhookHistoryClient < Voip::ServiceHistoryClient
  def initialize(service)
    super
    @service = service
  end

  def fetch_webhook_events(cursor: nil, limit: 100)
    validate_arguments!(cursor, limit)
    uri = configured_uri!
    uri.path = "#{uri.path.delete_suffix('/')}/v1/console/history"
    uri.query = URI.encode_www_form(scope.merge(sync: 'webhook_events', limit: limit).merge(cursor ? { cursor: cursor } : {}))
    headers = { 'Authorization' => "Bearer #{credentials['history_api_token']}", 'Accept' => 'application/json' }
    options = SafeFetch::RequestOptions.new(url: uri.to_s, open_timeout: 3, read_timeout: 10, headers: headers)
    payload = JSON.parse(read_response(options, nil))
    validate_events!(payload, limit)
    payload
  rescue JSON::ParserError, EncodingError
    raise ResponseError, 'Invalid webhook history JSON', cause: nil
  rescue SafeFetch::Error, SsrfFilter::Error, Resolv::ResolvError, Net::OpenTimeout, Net::ReadTimeout,
         SocketError, OpenSSL::SSL::SSLError, IOError, SystemCallError
    raise ConnectionError, 'Webhook history connection failed', cause: nil
  end

  private

  def scope
    company = credentials['history_company_id']
    raise ConfigurationError, 'History company is required' unless company.is_a?(String) && company.present?

    { 'company_id' => company, 'account_id' => @service.account_id.to_s, 'service_id' => @service.id.to_s,
      'source_instance_id' => credentials.fetch('webhook_source_instance_id') }
  end

  def validate_events!(payload, limit)
    valid = valid_envelope?(payload) && payload['scope'] == scope && payload['items'].is_a?(Array) && payload['items'].size <= limit
    raise ResponseError, 'Invalid webhook history scope or envelope' unless valid

    payload['items'].each { |item| validate_event!(item) }
  rescue ArgumentError
    raise ResponseError, 'Invalid canonical webhook event', cause: nil
  end

  def validate_event!(item)
    raise ResponseError, 'Invalid webhook history item' unless item.is_a?(Hash)

    event = item['webhook_event']
    valid = item['sequence'].is_a?(Integer) && event.is_a?(Hash) && item['sequence'] == event['revision']
    raise ResponseError, 'Invalid webhook history revision' unless valid

    Voip::ProviderEventContract.validate!(event, source: scope.fetch('source_instance_id'))
  end
end
