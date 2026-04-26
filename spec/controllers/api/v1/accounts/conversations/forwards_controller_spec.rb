require 'rails_helper'

RSpec.describe 'Conversation Forwards API', type: :request do
  let!(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:source_inbox) { create(:inbox, account: account) }
  let!(:source_conversation) { create(:conversation, account: account, inbox: source_inbox) }
  let!(:source_message) do
    create(:message, account: account, conversation: source_conversation, inbox: source_inbox, content: 'mensagem encaminhada')
  end

  before do
    create(:inbox_member, inbox: source_inbox, user: agent)
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/{conversation.id}/forwards' do
    it 'creates the target whatsapp contact inbox using bsuid when the contact has no phone number' do
      target_contact = create(:contact, account: account, phone_number: nil, bsuid: '123456789012345@lid')
      whatsapp_channel = create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
      target_inbox = whatsapp_channel.inbox

      post "/api/v1/accounts/#{account.id}/conversations/#{source_conversation.display_id}/forwards",
           params: {
             target_contact_id: target_contact.id,
             target_inbox_id: target_inbox.id,
             message_ids: [source_message.id]
           },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      contact_inbox = ContactInbox.find_by!(contact: target_contact, inbox: target_inbox)
      expect(contact_inbox.source_id).to eq('123456789012345@lid')
      expect(contact_inbox.conversations.last.messages.last.content).to eq("<p>mensagem encaminhada</p>\n")
    end

    it 'creates the target whatsapp contact inbox using phone number when phone number and bsuid are present' do
      target_contact = create(:contact, account: account, phone_number: '+5565999990000', bsuid: '123456789012345@lid')
      whatsapp_channel = create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
      target_inbox = whatsapp_channel.inbox

      post "/api/v1/accounts/#{account.id}/conversations/#{source_conversation.display_id}/forwards",
           params: {
             target_contact_id: target_contact.id,
             target_inbox_id: target_inbox.id,
             message_ids: [source_message.id]
           },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      contact_inbox = ContactInbox.find_by!(contact: target_contact, inbox: target_inbox)
      expect(contact_inbox.source_id).to eq('5565999990000')
    end
  end
end
