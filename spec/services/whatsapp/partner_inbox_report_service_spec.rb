require 'rails_helper'

RSpec.describe Whatsapp::PartnerInboxReportService do
  let(:account) { create(:account, reporting_timezone: 'America/Cuiaba') }
  let(:params) { { from: '2026-10-01', to: '2026-10-23', service_rate: '0.035' } }
  let(:service) { described_class.new(account: account, params: params) }
  let(:time) { Time.iso8601('2026-10-20T10:00:00-04:00') }
  let(:incoming) do
    { id: 0, created_at: time, direction: 'incoming', business_phone: '5511999999999', contact_id: 1,
      received_providers: ['unoapi'], provider: 'unoapi' }
  end
  let(:delivery) do
    { id: 1, created_at: time + 1.minute, direction: 'outgoing', business_phone: '5511999999999',
      contact_id: 1, provider: 'whatsapp_cloud', delivered: true, template: false }
  end

  it 'recalculates the hypothetical monthly allowance without counting failed or unidentified sends as savings' do
    rows = [incoming, delivery] + Array.new(1000) { |i| delivery.merge(id: i + 2, provider: 'unoapi') }
    rows << delivery.merge(id: 1002, provider: 'unknown')
    rows << delivery.merge(id: 1003, provider: 'unoapi', delivered: false)
    allow(service).to receive(:load_rows).and_return(rows)
    result = service.perform
    expect(result[:simulation][:estimated_cost]).to eq('0.0')
    expect(result[:simulation][:comparison]).to include(all_meta_cost: '0.035', avoided_meta_cost: '0.035', avoided_percent: '100.0')
    day = result[:daily].find { |item| item[:date] == '2026-10-20' }
    expect(day[:counts]['unoapi']).to include(outgoing: 1001, delivered: 1000)
    expect(day[:counts]['whatsapp_cloud']).to include(outgoing: 1, delivered: 1)
    expect(rows.count { |row| row[:provider] == 'unoapi' }).to eq(1002)
  end

  it 'reports missing category and rate evidence rather than inventing savings' do
    rows = [delivery.merge(provider: 'unoapi'), delivery.merge(id: 2, provider: 'unoapi', template: true, category: 'marketing')]
    allow(service).to receive(:load_rows).and_return(rows)
    comparison = service.perform[:simulation][:comparison]
    expect(comparison).to include(unclassified: 1, unpriced: 1, all_meta_cost: '0.0', avoided_meta_cost: '0.0', avoided_percent: nil)
  end
end
