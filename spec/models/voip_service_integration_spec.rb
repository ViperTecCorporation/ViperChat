require 'rails_helper'

RSpec.describe VoipService do
  let(:service) do
    described_class.new(account: create(:account), name: 'Central', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test')
  end

  it 'accepts webhook without AMI or REST but requires a stable source identity' do
    service.credentials = { integration_provider: 'webhook', webhook_source_instance_id: 'pbx-1' }
    expect(service).to be_valid
    service.credentials = { integration_provider: 'webhook' }
    expect(service).not_to be_valid
    expect(service.errors.attribute_names).to include(:webhook_source_instance_id)
  end

  it 'rejects obsolete AMI as active integration' do
    service.credentials = { integration_provider: 'asterisk_ami' }
    expect(service).not_to be_valid
  end

  it 'requires secure REST and a token for our service, without exposing the secret' do
    service.credentials = { integration_provider: 'viperconnect', webhook_source_instance_id: 'voice-1',
                            history_api_url: 'http://pbx.example.test', history_api_token: 'synthetic-secret' }
    expect(service).not_to be_valid
    service.credentials = service.credentials.merge('history_api_url' => 'https://pbx.example.test')
    expect(service).to be_valid
    expect(service.integration_payload).not_to have_key('history_api_token')
  end
end
