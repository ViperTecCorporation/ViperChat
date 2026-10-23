# Estimates only: this does not authorize sends, change transport, or represent a Meta invoice.
class Whatsapp::PartnerCostSimulationService
  CATEGORIES = %w[service utility marketing authentication].freeze

  def initialize(timezone:, rates:, ad_window_days: 7, monthly_allowance: 1000)
    @zone = ActiveSupport::TimeZone[timezone]
    @rates = rates
    @ad_window = ad_window_days.days
    @allowance = monthly_allowance
  end

  def perform(rows:, since:, until_time:)
    @since = since
    @until = until_time
    @usage = Hash.new(0)
    @incoming = {}
    @referrals = {}
    @windows = {}
    @result = { free_allowance: 0, free_ad: 0, free_customer_window: 0, chargeable: 0, unclassified: 0, unpriced: 0,
                estimated_cost: BigDecimal(0) }
    rows.sort_by { |row| [row[:created_at], row[:id]] }.each { |row| process(row) }
    @result.merge(months: months, estimated_cost: @result[:estimated_cost].to_s('F'))
  end

  private

  def process(row)
    key = [row[:business_phone], row[:contact_id]]
    if row[:direction] == 'incoming'
      @incoming[key] = row[:created_at]
      @referrals[key] = row[:created_at] if row[:ad_referral]
    elsif row[:provider] == 'whatsapp_cloud' && row[:delivered]
      process_delivery(row, key)
    end
  end

  def process_delivery(row, key)
    time = row[:created_at]
    open_ad_window(key, time)
    category = category_for(row, key)
    month = [row[:business_phone], time.in_time_zone(@zone).strftime('%Y-%m')]
    outcome = classify(key, time, category, month)
    return unless time >= @since && time < @until

    @result[outcome] += 1
    add_cost(category) if outcome == :chargeable
  end

  def category_for(row, key)
    return row[:category] if row[:category].present? || row[:template]

    'service' if @incoming[key] && row[:created_at] - @incoming[key] <= 24.hours
  end

  def open_ad_window(key, time)
    return unless @referrals[key] && time >= @referrals[key] && time - @referrals[key] <= 24.hours

    @windows[key] = time + @ad_window
    @referrals.delete(key)
  end

  def classify(key, time, category, month)
    @usage[month] += 0
    free = free_window_outcome(key, time, category)
    return free if free
    return CATEGORIES.include?(category) ? :chargeable : :unclassified unless category == 'service'

    @usage[month] += 1
    @usage[month] <= @allowance ? :free_allowance : :chargeable
  end

  def free_window_outcome(key, time, category)
    return :free_ad if @windows[key] && time < @windows[key]

    :free_customer_window if category == 'utility' && customer_window?(key, time)
  end

  def customer_window?(key, time)
    @incoming[key] && time - @incoming[key] <= 24.hours
  end

  def months
    @usage.filter_map do |(phone, month), count|
      next if month < @since.in_time_zone(@zone).strftime('%Y-%m')

      { business_phone: phone, month: month, service_delivered: count, allowance_used: [count, @allowance].min,
        allowance_remaining: [@allowance - count, 0].max }
    end
  end

  def add_cost(category)
    rate = @rates[category]
    if rate.nil?
      @result[:unpriced] += 1
    else
      @result[:estimated_cost] += rate
    end
  end
end
