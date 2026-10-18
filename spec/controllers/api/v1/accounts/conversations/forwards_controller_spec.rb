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
    it 'uses the ordinary contact inbox builder for an unlinked email inbox' do
      target_contact = create(:contact, account: account, email: 'synthetic-forward@example.invalid')
      email_channel = create(:channel_email, account: account)
      create(:inbox_member, inbox: email_channel.inbox, user: agent)
      expect(Whatsapp::OperationalInboxService).not_to receive(:contact_inbox)

      post "/api/v1/accounts/#{account.id}/conversations/#{source_conversation.display_id}/forwards",
           params: { target_contact_id: target_contact.id, target_inbox_id: email_channel.inbox.id, message_ids: [source_message.id] },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ContactInbox.find_by!(contact: target_contact, inbox: email_channel.inbox).source_id).to eq(target_contact.email)
    end

    it 'creates the target whatsapp contact inbox using bsuid when the contact has no phone number' do
      target_contact = create(:contact, account: account, phone_number: nil, bsuid: '123456789012345@lid')
      whatsapp_channel = create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
      target_inbox = whatsapp_channel.inbox
      create(:inbox_member, inbox: target_inbox, user: agent)

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
      create(:inbox_member, inbox: target_inbox, user: agent)

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

    it 'creates the target whatsapp contact inbox using group id when the contact is a group' do
      target_contact = create(:contact, account: account, email: '120363040468224422@g.us', phone_number: nil)
      whatsapp_channel = create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
      target_inbox = whatsapp_channel.inbox
      create(:inbox_member, inbox: target_inbox, user: agent)

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
      expect(contact_inbox.source_id).to eq('120363040468224422@g.us')
    end

    it 'forwards directly to an existing group conversation' do
      target_contact = create(:contact, account: account, email: '120363040468224422@g.us', phone_number: nil)
      whatsapp_channel = create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
      target_inbox = whatsapp_channel.inbox
      target_contact_inbox = create(
        :contact_inbox,
        contact: target_contact,
        inbox: target_inbox,
        source_id: '120363040468224422@g.us'
      )
      target_conversation = create(
        :conversation,
        account: account,
        inbox: target_inbox,
        contact: target_contact,
        contact_inbox: target_contact_inbox,
        group: true,
        group_title: 'Equipe Comercial',
        group_source_id: '120363040468224422@g.us'
      )
      create(:inbox_member, inbox: target_inbox, user: agent)

      expect do
        post "/api/v1/accounts/#{account.id}/conversations/#{source_conversation.display_id}/forwards",
             params: {
               target_conversation_id: target_conversation.display_id,
               message_ids: [source_message.id]
             },
             headers: agent.create_new_auth_token,
             as: :json
      end.not_to change(Conversation, :count)

      expect(response).to have_http_status(:success)
      expect(target_conversation.reload.messages.last.content).to eq("<p>mensagem encaminhada</p>\n")
    end
  end

  describe 'forward authorization and source selection' do
    let!(:target_inbox) { create(:inbox, account: account) }
    let!(:target_contact) { create(:contact, account: account) }
    let!(:target_contact_inbox) { create(:contact_inbox, contact: target_contact, inbox: target_inbox) }
    let!(:target_conversation) do
      create(:conversation, account: account, inbox: target_inbox, contact: target_contact, contact_inbox: target_contact_inbox)
    end
    let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{source_conversation.display_id}/forwards" }
    let(:params) { { target_conversation_id: target_conversation.display_id, message_ids: [source_message.id] } }

    before { create(:inbox_member, inbox: target_inbox, user: agent) }

    it 'rejects a mixed selection from another conversation rather than forwarding a partial batch' do
      other_message = create(:message, account: account)
      params[:message_ids] << other_message.id

      expect { post path, params: params, headers: agent.create_new_auth_token, as: :json }.not_to change(Message, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects a cross-account source' do
      params[:message_ids] << create(:message).id

      expect { post path, params: params, headers: agent.create_new_auth_token, as: :json }.not_to change(Message, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects missing IDs rather than silently skipping them' do
      params[:message_ids] << 0

      expect { post path, params: params, headers: agent.create_new_auth_token, as: :json }.not_to change(Message, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects an unauthorized source conversation' do
      source_inbox.inbox_members.where(user: agent).destroy_all

      post path, params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(target_conversation.reload.messages).to be_empty
    end

    it 'rejects an unauthorized target before reassigning it' do
      target_inbox.inbox_members.where(user: agent).destroy_all

      post path, params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(target_conversation.reload.assignee_id).not_to eq(agent.id)
    end

    it 'rejects private notes without making them public' do
      source_message.update!(private: true)

      expect { post path, params: params, headers: agent.create_new_auth_token, as: :json }.not_to change(Message, :count)

      expect(response).not_to have_http_status(:success)
    end

    it 'passes only the root transport selection to the forwarding service' do
      params[:whatsapp_transport] = 'unoapi'
      forwarding = instance_double(Messages::ForwardService, perform: target_conversation)
      expect(Messages::ForwardService).to receive(:new).with(hash_including(requested_provider: 'unoapi')).and_return(forwarding)

      post path, params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'requires authorization for contact/inbox destinations too' do
      target_inbox.inbox_members.where(user: agent).destroy_all

      post path, params: { target_contact_id: target_contact.id, target_inbox_id: target_inbox.id, message_ids: [source_message.id] },
                 headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
