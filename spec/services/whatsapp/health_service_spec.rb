require 'rails_helper'

RSpec.describe Whatsapp::HealthService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).tap do |record|
      record.provider_config.merge!('api_key' => 'synthetic-secret', 'business_account_id' => 'test-waba', 'phone_number_id' => 'test-phone')
    end
  end

  before do
    stub_request(:get, %r{https://graph.facebook.com/v[\d.]+/test-phone})
      .with { |request| !CGI.parse(request.uri.query)['fields'].sole.split(',').include?('messaging_limit_tier') }
      .to_return(status: 200, body: { id: 'test-phone', quality_rating: 'GREEN', messaging_limit_tier: 'TIER_250' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  it 'uses the current portfolio limit instead of the old 250 value and preserves the old response key for apps' do
    stub_request(:get, %r{https://graph.facebook.com/v[\d.]+/test-waba})
      .with(query: { fields: 'whatsapp_business_manager_messaging_limit' }, headers: { Authorization: 'Bearer synthetic-secret' })
      .to_return(status: 200, body: { whatsapp_business_manager_messaging_limit: 'TIER_2K' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    data = described_class.new(channel).fetch_health_status
    expect(data).to include(messaging_limit_tier: 'TIER_2K', whatsapp_business_manager_messaging_limit: 'TIER_2K',
                           messaging_limit_scope: 'business_portfolio', quality_rating: 'GREEN')
    expect(data[:fetched_at]).to be_present
  end

  it 'keeps health available but explicitly unknown if the limit is unavailable' do
    stub_request(:get, %r{https://graph.facebook.com/v[\d.]+/test-waba}).to_return(status: 403, body: '{}',
                                                                                            headers: { 'Content-Type' => 'application/json' })
    expect(described_class.new(channel).fetch_health_status).to include(messaging_limit_tier: nil, messaging_limit_scope: 'unknown',
                                                                      quality_rating: 'GREEN')
  end

  it 'does not propagate Graph error payloads or tokens' do
    stub_request(:get, %r{https://graph.facebook.com/v[\d.]+/test-phone})
      .to_return(status: 403, body: { error: { code: 190, message: 'synthetic-secret' } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    expect { described_class.new(channel).fetch_health_status }
      .to raise_error(Whatsapp::ManagementApiClient::Error, 'WhatsApp management data is unavailable')
  end
end
