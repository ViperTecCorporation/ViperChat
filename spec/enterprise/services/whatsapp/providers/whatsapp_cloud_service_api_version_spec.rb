require 'rails_helper'

RSpec.describe Whatsapp::Providers::WhatsappCloudService do
  let(:channel) do
    instance_double(Channel::Whatsapp, provider: 'whatsapp_cloud',
                                       provider_config: { 'phone_number_id' => 'phone', 'api_key' => 'token' })
  end
  let(:cloud) { described_class.new(whatsapp_channel: channel) }

  before do
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', 'v26.0').and_return('v26.0')
  end

  it 'uses the configured Meta version for Enterprise call actions' do
    request = stub_request(:post, 'https://graph.facebook.com/v26.0/phone/calls')
              .with(body: { messaging_product: 'whatsapp', call_id: 'call', action: 'reject' }.to_json)
              .to_return(body: '{}', headers: { 'Content-Type' => 'application/json' })
    expect(cloud.reject_call('call')).to be(true)
    expect(request).to have_been_requested
  end

  it 'uses the configured Meta version for call permission requests' do
    request = stub_request(:post, 'https://graph.facebook.com/v26.0/phone/messages')
              .with(body: hash_including(type: 'interactive'))
              .to_return(body: '{"messages":[]}', headers: { 'Content-Type' => 'application/json' })
    expect(cloud.send_call_permission_request('15555555555')).to eq('messages' => [])
    expect(request).to have_been_requested
  end
end
