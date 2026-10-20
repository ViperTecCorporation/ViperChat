# Informational only: no message routing, template changes or provider sends.
class Whatsapp::AccountInsightsService
  PERIODS = [7, 30, 90].freeze
  CACHE_DURATION = 10.minutes
  FIELDS = { messages: 'analytics', pricing: 'pricing_analytics', calls: 'call_analytics' }.freeze
  POINT_FIELDS = %w[start end sent delivered received volume cost pricing_category pricing_type phone_number country
                    currency count average_duration direction product_type].freeze

  def initialize(channel:, days: 30)
    @channel = channel
    @days = Integer(days.to_s, 10)
    raise ArgumentError, 'Unsupported insights period' unless PERIODS.include?(@days)

    @client = Whatsapp::ManagementApiClient.new(channel)
  end

  def perform
    config = @channel.provider_config
    key = ['whatsapp-account-insights-v2', @channel.account_id, @channel.id, @channel.updated_at.to_i,
           Digest::SHA256.hexdigest(config.slice('api_key', 'business_account_id', 'phone_number_id').to_json), @days]
    Rails.cache.fetch(key, expires_in: CACHE_DURATION) { fetch }
  end

  private

  def fetch
    @end_at = Time.current.beginning_of_day
    @start_at = @end_at - @days.days
    requests = FIELDS.transform_values { |field| Concurrent::Promises.future { fetch_section(field) } }
    currency = Concurrent::Promises.future { fetch_currency }
    sections = requests.transform_values(&:value!)
    {
      informational_only: true, period: { days: @days, start: @start_at.iso8601, end: @end_at.iso8601 },
      fetched_at: Time.current.iso8601, cached_until: CACHE_DURATION.from_now.iso8601,
      currency: currency.value!, sections: sections
    }
  end

  def fetch_section(field)
    phone = @channel.phone_number.to_s.gsub(/\D/, '')
    return { status: 'unavailable', reason: 'configuration_missing', data: nil } if phone.blank?

    data = @client.get(@channel.provider_config['business_account_id'], fields: field_query(field, phone))[field]
    return { status: 'unavailable', reason: 'not_returned', data: nil } unless data.is_a?(Hash)

    result = { status: 'available', data: sanitize_data(data) }
    if field == 'analytics'
      received = fetch_received(phone)
      result[:received_status] = received[:status]
      result[:received_reason] = received[:reason]
      result[:data]['received_data_points'] = received[:data]
    end
    result
  rescue Whatsapp::ManagementApiClient::Error => e
    { status: 'unavailable', reason: e.reason, data: nil }
  end

  def field_query(field, phone)
    granularity = field == 'analytics' ? 'DAY' : 'DAILY'
    query = "#{field}.start(#{@start_at.to_i}).end(#{@end_at.to_i}).granularity(#{granularity}).phone_numbers(#{[phone].to_json})"
    return "#{query}.product_types([0,2])" if field == 'analytics'
    return "#{query}.dimensions([\"PRICING_CATEGORY\",\"PRICING_TYPE\",\"PHONE\"])" if field == 'pricing_analytics'

    "#{query}.dimensions([\"DIRECTION\",\"PHONE\"])"
  end

  def fetch_received(phone)
    query = field_query('analytics', phone).sub('product_types([0,2])', 'product_types([100])')
    data = @client.get(@channel.provider_config['business_account_id'], fields: query)['analytics']
    return { status: 'unavailable', reason: 'not_returned', data: nil } unless data.is_a?(Hash)

    { status: 'available', data: sanitize_points(data['data_points']) }
  rescue Whatsapp::ManagementApiClient::Error => e
    { status: 'unavailable', reason: e.reason, data: nil }
  end

  def sanitize_data(data)
    result = {}
    result['data_points'] = sanitize_points(data['data_points']) if data['data_points'].is_a?(Array)
    result['data'] = data['data'].filter_map { |entry| sanitize_data(entry) if entry.is_a?(Hash) } if data['data'].is_a?(Array)
    result
  end

  def sanitize_points(points)
    Array(points).filter_map { |point| point.slice(*POINT_FIELDS) if point.is_a?(Hash) }
  end

  def fetch_currency
    data = @client.get(@channel.provider_config['business_account_id'], fields: 'currency')
    data['currency'].presence
  rescue Whatsapp::ManagementApiClient::Error
    nil
  end
end
