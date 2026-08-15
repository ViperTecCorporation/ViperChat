require 'rails_helper'

RSpec.describe Messages::ForwardService do
  subject(:service) do
    described_class.new(
      account: account,
      user: user,
      source_messages: [source_message],
      target_contact_inbox: lid_contact_inbox
    )
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:source_conversation) { create(:conversation, account: account) }
  let(:source_message) { create(:message, account: account, conversation: source_conversation, content: 'Forward me') }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'unoapi',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5566999535182', bsuid: '19357434396794@lid') }
  let!(:phone_contact_inbox) do
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566999535182')
  end
  let!(:lid_contact_inbox) do
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: '19357434396794@lid')
  end
  let!(:existing_conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: phone_contact_inbox)
  end

  context 'when the inbox is locked to a single conversation' do
    before { inbox.update!(lock_to_single_conversation: true) }

    it 'reuses the conversation from another source alias of the same contact' do
      result = service.perform

      expect(result).to eq(existing_conversation)
      expect(contact.conversations.where(inbox: inbox).count).to eq(1)
      expect(existing_conversation.messages.last.content).to eq("<p>Forward me</p>\n")
    end
  end

  context 'when the inbox allows multiple conversations' do
    before { inbox.update!(lock_to_single_conversation: false) }

    it 'keeps conversations separated by source alias' do
      result = service.perform

      expect(result).not_to eq(existing_conversation)
      expect(result.contact_inbox).to eq(lid_contact_inbox)
      expect(contact.conversations.where(inbox: inbox).count).to eq(2)
    end
  end
end
