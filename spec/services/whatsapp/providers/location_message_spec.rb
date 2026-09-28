require 'rails_helper'

[Whatsapp::Providers::WhatsappCloudService, Whatsapp::Providers::UnoapiService].each do |provider|
  describe provider do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
    let(:conversation) { create(:conversation, inbox: channel.inbox, account: channel.account) }
    let(:message) { create(:message, conversation: conversation, inbox: channel.inbox, account: channel.account, message_type: :outgoing) }
    let(:service) { described_class.new(whatsapp_channel: channel) }
    let(:endpoint) { 'https://location-provider.example/messages' }

    before do
      message.attachments.create!(account: channel.account, file_type: :location, coordinates_lat: 0, coordinates_long: -55.5,
                                  meta: { name: 'Local', address: 'Rua A' })
      allow(service).to receive(:phone_id_path).and_return('https://location-provider.example')
      allow(service).to receive(:api_headers).and_return({})
    end

    it 'sends native location JSON instead of a document' do
      request = stub_request(:post, endpoint).with do |req|
        payload = JSON.parse(req.body)
        payload['type'] == 'location' && payload['to'] == '5511999999999' &&
          payload['location'] == { 'latitude' => 0.0, 'longitude' => -55.5, 'name' => 'Local', 'address' => 'Rua A' }
      end.to_return(status: 200, body: { messages: [{ id: 'location-id' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
      expect(service.send_message('5511999999999', message)).to eq('location-id')
      expect(request).to have_been_requested.once
    end

    it 'keeps provider errors on the failed-message path' do
      stub_request(:post, endpoint).to_return(status: 400, body: { error: { message: 'Invalid location' } }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })
      expect(service.send_message('5511999999999', message)).to be_nil
      expect(message.reload.status).to eq('failed')
    end
  end
end
