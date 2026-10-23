require 'rails_helper'

RSpec.describe Whatsapp::PartnerCostSimulationService do
  let(:rates) do
    { 'service' => BigDecimal('0.035'), 'utility' => BigDecimal('0.035'),
      'authentication' => BigDecimal('0.035'), 'marketing' => BigDecimal('0.3217') }
  end
  let(:service) { described_class.new(timezone: 'America/Cuiaba', rates: rates) }
  let(:time) { Time.iso8601('2026-10-20T10:00:00-04:00') }
  let(:incoming) { { id: 0, created_at: time, direction: 'incoming', business_phone: '5511999999999', contact_id: 1 } }
  let(:delivery) do
    { id: 1, created_at: time + 1.minute, direction: 'outgoing', business_phone: '5511999999999',
      contact_id: 1, provider: 'whatsapp_cloud', delivered: true, template: false }
  end

  { 1000 => '0.0', 5000 => '140.0', 10_000 => '315.0', 50_000 => '1715.0', 100_000 => '3465.0' }.each do |count, cost|
    it "prices #{count} service deliveries after the exclusive monthly allowance" do
      rows = [incoming] + Array.new(count) { |i| delivery.merge(id: i + 1) }
      result = service.perform(rows: rows, since: time.beginning_of_month, until_time: time.end_of_month)
      expect(BigDecimal(result[:estimated_cost])).to eq(BigDecimal(cost))
      expect(result).to include(free_allowance: 1000, chargeable: count - 1000)
    end
  end

  it 'charges all template categories inside 24 hours in October without consuming service allowance' do
    rows = [incoming] + %w[utility authentication marketing].each_with_index.map do |category, i|
      delivery.merge(id: i + 1, template: true, category: category)
    end
    result = service.perform(rows: rows, since: time.beginning_of_month, until_time: time.end_of_month)
    expect(result).to include(free_allowance: 0, free_customer_window: 0, chargeable: 3)
    expect(BigDecimal(result[:estimated_cost])).to eq(BigDecimal('0.3917'))
  end

  it 'preserves the earlier service and in-window utility exemptions before October' do
    rows = [incoming.merge(created_at: time - 1.month), delivery.merge(created_at: time - 1.month + 1.minute),
            delivery.merge(id: 2, created_at: time - 1.month + 2.minutes, template: true, category: 'utility')]
    result = service.perform(rows: rows, since: time.prev_month.beginning_of_month, until_time: time.beginning_of_month)
    expect(result).to include(free_customer_window: 2, chargeable: 0, free_allowance: 0)
  end

  it 'exempts every category during a confirmed seven-day ad scenario, then resumes normal pricing' do
    rows = [incoming.merge(ad_referral: true), delivery] + %w[utility authentication marketing].each_with_index.map do |category, i|
      delivery.merge(id: i + 2, created_at: time + 6.days, template: true, category: category)
    end
    rows << delivery.merge(id: 5, created_at: time + 7.days + 1.minute, template: true, category: 'marketing')
    result = service.perform(rows: rows, since: time.beginning_of_month, until_time: time.end_of_month)
    expect(result).to include(free_ad: 4, free_allowance: 0, chargeable: 1)
    expect(result[:ad_leads].first).to include(contact_id: 1, window_days: 7, free_meta_messages: 4,
                                             window_start: time + 1.minute, window_end: time + 7.days + 1.minute)
    expect(BigDecimal(result[:estimated_cost])).to eq(BigDecimal('0.3217'))
  end

  it 'does not open an ad window after a late response or from a normal incoming message' do
    rows = [incoming.merge(ad_referral: true), delivery.merge(created_at: time + 25.hours, template: true, category: 'marketing')]
    result = service.perform(rows: rows, since: time.beginning_of_month, until_time: time.end_of_month)
    expect(result).to include(free_ad: 0, chargeable: 1)
    expect(result[:ad_leads].first[:window_start]).to be_nil
    rows = [incoming, delivery.merge(template: true, category: 'marketing')]
    expect(service.perform(rows: rows, since: time.beginning_of_month, until_time: time.end_of_month)).to include(free_ad: 0, chargeable: 1)
  end

  it 'resets the allowance at the local month boundary and keeps each business number separate' do
    rows = [delivery.merge(created_at: Time.iso8601('2026-11-01T03:59:59Z'), category: 'service'),
            delivery.merge(id: 2, created_at: Time.iso8601('2026-11-01T04:00:00Z'), category: 'service'),
            delivery.merge(id: 3, created_at: Time.iso8601('2026-11-01T04:00:01Z'), category: 'service', business_phone: '5521999999999')]
    result = service.perform(rows: rows, since: time.beginning_of_month, until_time: time.next_month.end_of_month)
    expect(result[:months].map { |month| month.values_at(:month, :service_delivered, :allowance_remaining) }).to eq(
      [['2026-10', 1, 999], ['2026-11', 1, 999], ['2026-11', 1, 999]]
    )
  end

  it 'does not charge inbound, undelivered or ViperConnect messages as Meta traffic' do
    rows = [incoming, delivery.merge(delivered: false), delivery.merge(id: 2, provider: 'unoapi')]
    expect(service.perform(rows: rows, since: time.beginning_of_month, until_time: time.end_of_month)).to include(chargeable: 0, free_allowance: 0)
  end
end
