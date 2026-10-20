require 'rails_helper'

RSpec.describe Whatsapp::AccountInsightsService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).tap do |record|
      record.provider_config.merge!('api_key' => 'synthetic-secret', 'business_account_id' => 'test-waba', 'phone_number_id' => 'test-phone')
    end
  end
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:url) { %r{https://graph.facebook.com/v[\d.]+/test-waba} }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it 'queries only the configured number with bearer authentication, caches and preserves real zero values', :aggregate_failures do
    requests = []
    stub_request(:get, url).with(headers: { 'Authorization' => 'Bearer synthetic-secret' }).to_return do |request|
      field = CGI.parse(request.uri.query)['fields'].sole
      requests << field
      name = field.split('.').first
      body = name == 'currency' ? { currency: 'BRL' } : { name => { data_points: [{ sent: 0, delivered: 0 }] } }
      { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    data = described_class.new(channel: channel).perform
    expect(data[:informational_only]).to be(true)
    expect(data[:currency]).to eq('BRL')
    expect(data.dig(:sections, :messages, :data, 'data_points')).to eq([{ 'sent' => 0, 'delivered' => 0 }])
    expect(requests.reject { |field| field == 'currency' }).to all(include("phone_numbers(#{[channel.phone_number.gsub(/\D/, '')].to_json})"))
    expect(described_class.new(channel: channel).perform).to eq(data)
    expect(requests.length).to eq(5)
    expect(requests).to include(include('product_types([100])'), include('product_types([0,2])'))
    expect(requests).not_to include(include('product_types([0,2,100])'))
    expect { described_class.new(channel: channel).perform }.not_to change(Message, :count)
  end

  it 'does not convert missing metrics or permission failures into zero and keeps other sections working' do
    stub_request(:get, url).to_return do |request|
      field = CGI.parse(request.uri.query)['fields'].sole
      if field.start_with?('pricing_analytics')
        { status: 403, body: { error: { code: 200, message: 'synthetic-secret' } }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      else
        { status: 200, body: (field == 'currency' ? {} : { field.split('.').first => { data_points: [] } }).to_json,
          headers: { 'Content-Type' => 'application/json' } }
      end
    end

    data = described_class.new(channel: channel, days: 7).perform
    expect(data.dig(:sections, :pricing)).to eq(status: 'unavailable', reason: 'permission_denied', data: nil)
    expect(data.dig(:sections, :messages, :status)).to eq('available')
    expect(data[:currency]).to be_nil
    expect(data.to_json).not_to include('synthetic-secret')
  end

  it 'rejects unsupported periods before any network request' do
    %w[0 1 365 30abc].each do |days|
      expect { described_class.new(channel: channel, days: days) }.to raise_error(ArgumentError)
    end
    expect(WebMock).not_to have_requested(:get, url)
  end

  it 'exposes an inbound-only failure without discarding outbound metrics' do
    stub_request(:get, url).to_return do |request|
      field = CGI.parse(request.uri.query)['fields'].sole
      if field.include?('product_types([100])')
        { status: 403, body: { error: { code: 200 } }.to_json, headers: { 'Content-Type' => 'application/json' } }
      else
        { status: 200, body: { analytics: { data_points: [{ sent: 3, delivered: 2 }] } }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      end
    end
    data = described_class.new(channel: channel).perform
    expect(data.dig(:sections, :messages)).to include(status: 'available', received_status: 'unavailable', received_reason: 'permission_denied')
    expect(data.dig(:sections, :messages, :data, 'data_points')).to eq([{ 'sent' => 3, 'delivered' => 2 }])
    expect(data.dig(:sections, :messages, :data, 'received_data_points')).to be_nil
  end

  it 'handles timeouts without exposing provider details or fabricating measurements' do
    stub_request(:get, url).to_timeout
    data = described_class.new(channel: channel, days: 90).perform
    expect(data[:sections].values).to all(eq(status: 'unavailable', reason: 'temporarily_unavailable', data: nil))
    expect(data[:currency]).to be_nil
  end

  it 'removes provider debug data and does not share cache entries between inboxes or periods' do
    stub_request(:get, url).to_return(status: 200, body: { analytics: { data_points: [{ sent: 2, token: 'private' }] } }.to_json,
                                      headers: { 'Content-Type' => 'application/json' })
    first = described_class.new(channel: channel).perform
    expect(first.dig(:sections, :messages, :data, 'data_points')).to eq([{ 'sent' => 2 }])
    expect(first.dig(:sections, :calls, :status)).to eq('unavailable')
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', account: channel.account,
                                      sync_templates: false, validate_provider_config: false, provider_config: channel.provider_config)
    other.provider_config = channel.provider_config
    described_class.new(channel: other).perform
    described_class.new(channel: channel, days: 7).perform
    expect(WebMock).to have_requested(:get, url).times(15)
  end
end
