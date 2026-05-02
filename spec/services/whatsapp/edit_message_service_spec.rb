require 'rails_helper'

RSpec.describe Whatsapp::EditMessageService do
  subject(:service) { described_class.new(message: message, content: 'edited text') }

  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, provider: 'unoapi', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+123456789') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '123456789') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:agent) { create(:user, account: account) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      content: 'original text',
      source_id: 'uno-original-id',
      sender: agent
    )
  end
  let(:channel) { message.conversation.inbox.channel }

  before do
    allow(channel).to receive(:send_message_edit).and_return('uno-edit-id')
  end

  it 'sends the edit to UnoAPI and updates the local message' do
    expect(service.perform).to be true
    expect(channel).to have_received(:send_message_edit).with('123456789', message, 'edited text')
    expect(message.reload.content).to eq('edited text')
    expect(message.content_attributes['edited']).to be true
    expect(message.content_attributes['edit_event_id']).to eq('uno-edit-id')
    expect(message.content_attributes['previous_content']).to eq('original text')
  end

  context 'when provider rejects the edit' do
    before do
      allow(channel).to receive(:send_message_edit).and_return(nil)
    end

    it 'does not update the local message' do
      expect(service.perform).to be false
      expect(message.reload.content).to eq('original text')
    end
  end
end
