require 'rails_helper'

RSpec.describe Whatsapp::ApiVersion do
  describe '.current' do
    it 'loads the v26.0 default' do
      expect(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', 'v26.0').and_return('v26.0')
      expect(described_class.current).to eq('v26.0')
    end

    it 'preserves an explicitly configured version' do
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', 'v26.0').and_return('v22.0')
      expect(described_class.current).to eq('v22.0')
    end

    [nil, '', '26.0', 'v26.1', 'v26.0/messages', "v26.0\n", 26].each do |invalid_version|
      it "rejects invalid configuration #{invalid_version.inspect}" do
        allow(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', 'v26.0').and_return(invalid_version)
        expect { described_class.current }.to raise_error(ArgumentError, /WHATSAPP_API_VERSION/)
      end
    end
  end

  describe 'provider version boundaries' do
    let(:channel) do
      instance_double(Channel::Whatsapp,
                      provider: 'whatsapp_cloud', unoapi_api_url: 'https://uno.example.com',
                      provider_config: { 'phone_number_id' => 'phone', 'business_account_id' => 'business', 'api_key' => 'token' })
    end
    let(:cloud) { Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel) }
    let(:uno) { Whatsapp::Providers::UnoapiService.new(whatsapp_channel: channel) }

    before do
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', 'v26.0').and_return('v26.0')
    end

    it 'uses the configured Meta version for phone, media, templates and CTA' do
      expect(cloud.send(:messages_path)).to eq('https://graph.facebook.com/v26.0/phone/messages')
      expect(cloud.send(:phone_id_path, :voice)).to eq('https://graph.facebook.com/v26.0/phone')
      expect(cloud.media_url('media')).to eq('https://graph.facebook.com/v26.0/media')
      expect(cloud.send(:business_account_path)).to eq('https://graph.facebook.com/v26.0/business')
      expect(cloud.web_invitation_messages_path).to eq('https://graph.facebook.com/v26.0/phone/messages')
    end

    it 'respects explicit Meta versions across provider paths' do
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', 'v26.0').and_return('v22.0')
      expect(cloud.send(:messages_path)).to eq('https://graph.facebook.com/v22.0/phone/messages')
      expect(cloud.media_url('media')).to eq('https://graph.facebook.com/v22.0/media')
      expect(cloud.send(:business_account_path)).to eq('https://graph.facebook.com/v22.0/business')
      expect(cloud.web_invitation_messages_path).to eq('https://graph.facebook.com/v22.0/phone/messages')
    end

    it 'keeps UnoAPI phone/media v13, business v14 and groups v15 independent of Meta config' do
      expect(GlobalConfigService).not_to receive(:load)
      expect(uno.send(:messages_path)).to eq('https://uno.example.com/v13.0/phone/messages')
      expect(uno.media_url('media')).to eq('https://uno.example.com/v13.0/media')
      expect(uno.send(:business_account_path)).to eq('https://uno.example.com/v14.0/business')
      expect(uno.web_invitation_messages_path).to eq('https://uno.example.com/v13.0/phone/messages')
      expect(uno.send(:phone_id_path, :voice)).to eq('https://uno.example.com/v24.0/phone')
      expect(uno.send(:unoapi_group_path, 'group')).to eq('https://uno.example.com/v15.0/phone/groups/group')
    end

    it 'keeps CSAT on the existing Meta endpoint even when invoked for UnoAPI' do
      allow(channel).to receive(:provider).and_return('unoapi')
      service = Whatsapp::CsatTemplateService.new(channel)
      expect(service.send(:business_account_path)).to eq('https://graph.facebook.com/v26.0/business')
    end

    it 'uses the same version for management requests' do
      stub_request(:get, 'https://graph.facebook.com/v26.0/phone')
        .with(query: { fields: 'id' })
        .to_return(body: '{"id":"phone"}', headers: { 'Content-Type' => 'application/json' })
      expect(Whatsapp::ManagementApiClient.new(channel).get('phone', fields: 'id')).to eq('id' => 'phone')
    end

    it 'uses the same version for embedded signup requests' do
      stub_request(:get, 'https://graph.facebook.com/v26.0/business/phone_numbers')
        .with(query: { access_token: 'token' })
        .to_return(body: '{"data":[]}', headers: { 'Content-Type' => 'application/json' })
      expect(Whatsapp::FacebookApiClient.new('token').fetch_phone_numbers('business')).to eq('data' => [])
    end
  end
end
