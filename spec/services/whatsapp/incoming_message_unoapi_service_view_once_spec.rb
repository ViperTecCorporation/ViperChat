require 'rails_helper'

RSpec.describe Whatsapp::IncomingMessageUnoapiService do
  let(:channel) { create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false) }
  let(:media_type) { 'image' }
  let(:payload) do
    {
      entry: [{ changes: [{ value: {
        metadata: { display_phone_number: channel.phone_number.delete('+') },
        contacts: [{ wa_id: '5566996269251', profile: { name: 'View once contact' } }],
        messages: [{ id: 'view-once-test', from: '5566996269251', timestamp: Time.current.to_i.to_s,
                     type: media_type, message_type: 'view_once' }.merge(media_type => { id: 'media-test', mime_type: 'image/png' })]
      } }] }]
    }.with_indifferent_access
  end

  %w[image video audio].each do |type|
    context "with #{type}" do
      let(:media_type) { type }

      it 'persists media and marker once without treating it as an edit' do
        service = described_class.new(inbox: channel.inbox, params: payload)
        allow(service).to receive(:download_attachment_file).and_return(fixture_file_upload('spec/assets/sample.png', 'image/png'))
        service.perform
        described_class.new(inbox: channel.inbox, params: payload).perform

        messages = channel.inbox.messages.where(source_id: 'view-once-test')
        expect(messages.count).to eq(1)
        received = messages.first.reload
        expect(received.content_attributes).to include('view_once' => true)
        expect(received.content_attributes['edited']).to be_falsey
        expect(received.attachments.count).to eq(1)
        expect(received.attachments.first.file_type).to eq(type)
      end
    end
  end
end
