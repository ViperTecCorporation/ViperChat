require 'rails_helper'

RSpec.describe 'Canonical WhatsApp new conversation', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:meta_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno_channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let!(:contact) do
    create(:contact, account: account, name: 'Existing human name', phone_number: '+5566996269251',
                     additional_attributes: { 'manual_reference' => 'preserve' })
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/conversations" }

  reuse_policies = [true, false].product(%w[open pending snoozed resolved])

  %w[whatsapp_cloud unoapi].each do |principal|
    context "with #{principal} principal" do
      let(:primary) { principal == 'whatsapp_cloud' ? meta_channel.inbox : uno_channel.inbox }
      let(:secondary) { principal == 'whatsapp_cloud' ? uno_channel.inbox : meta_channel.inbox }
      let!(:link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: primary, secondary_inbox: secondary,
                                  default_provider: 'unoapi', enabled: true)
      end
      let!(:primary_alias) do
        create(:contact_inbox, contact: contact, inbox: primary,
                               source_id: principal == 'whatsapp_cloud' ? '556696269251' : '5566996269251')
      end
      let!(:secondary_alias) do
        create(:contact_inbox, contact: contact, inbox: secondary,
                               source_id: principal == 'whatsapp_cloud' ? '5566996269251' : '556696269251')
      end
      let(:params) do
        { inbox_id: secondary.id, contact_id: contact.id, source_id: secondary_alias.source_id,
          message: { content: 'Synthetic compose', message_type: 'outgoing' }, assignee_id: admin.id }
      end

      %w[whatsapp_cloud unoapi].each do |provider|
        it "persists explicitly selected #{provider} on a canonical message without inheriting public IDs" do
          legacy = create(:conversation, account: account, inbox: secondary, contact: contact, contact_inbox: secondary_alias)
          old_message = create(:message, account: account, inbox: secondary, conversation: legacy,
                                         source_id: 'legacy-provider-public-id', content: 'Historical message')
          legacy_snapshot = legacy.reload.attributes
          message_snapshot = old_message.reload.attributes
          params[:message][:whatsapp_transport] = provider

          expect do
            post endpoint, params: params, headers: admin.create_new_auth_token, as: :json
          end.not_to change(Contact, :count)

          expect(response).to have_http_status(:success)
          conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('id'))
          message = conversation.messages.where(message_type: :outgoing).last
          aggregate_failures 'canonical ownership and independent public identity' do
            expect(conversation).to have_attributes(inbox_id: primary.id, contact_id: contact.id, contact_inbox_id: primary_alias.id)
            expect(message.inbox_id).to eq(primary.id)
            expect(message.content_attributes.fetch('whatsapp_transport')).to include(
              'link_id' => link.id, 'requested_provider' => provider, 'provider' => provider,
              'inbox_id' => link.inbox_for(provider).id
            )
            expect(message.source_id).to be_blank
            expect(message.content_attributes['provider_message_id']).to be_blank
            expect(WhatsappUnifiedMessageAlias.where(message: message)).to be_empty
          end
          expect(primary_alias.reload.source_id).not_to eq(secondary_alias.reload.source_id)
          expect(legacy.reload.attributes).to eq(legacy_snapshot)
          expect(old_message.reload.attributes).to eq(message_snapshot)
        end
      end

      it 'supports old requests without a transport field using the link default' do
        post endpoint, params: params, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('id'))
        expect(conversation.inbox_id).to eq(primary.id)
        expect(conversation.messages.where(message_type: :outgoing).last.content_attributes.fetch('whatsapp_transport'))
          .to include('requested_provider' => 'unoapi', 'provider' => 'unoapi')
      end

      it 'resolves legacy source-only secondary requests through the original contact' do
        params.delete(:contact_id)

        post endpoint, params: params, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('id'))
        expect(conversation).to have_attributes(inbox_id: primary.id, contact_id: contact.id, contact_inbox_id: primary_alias.id)
        expect(primary_alias.reload.source_id).to eq(principal == 'whatsapp_cloud' ? '556696269251' : '5566996269251')
      end

      reuse_policies.each do |unique, status|
        it "#{unique || status != 'resolved' ? 'reuses' : 'replaces'} #{status} with unique=#{unique}, preserving the existing owner" do
          primary.update!(lock_to_single_conversation: unique)
          owner = create(:user, account: account, role: :agent)
          create(:inbox_member, user: owner, inbox: primary)
          existing = create(:conversation, account: account, inbox: primary, contact: contact, contact_inbox: primary_alias,
                                           assignee: owner, status: status)
          params.delete(:message)
          reuse = unique || status != 'resolved'
          before_count = account.conversations.count

          post endpoint, params: params, headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          result = account.conversations.find_by!(display_id: response.parsed_body.fetch('id'))
          expect(account.conversations.count).to eq(before_count + (reuse ? 0 : 1))
          if reuse
            expect(result.id).to eq(existing.id)
            expect(result.assignee_id).to eq(owner.id)
            expect(result.status).to eq(status == 'resolved' ? 'open' : status)
          else
            expect(result.id).not_to eq(existing.id)
            expect(existing.reload.status).to eq('resolved')
          end
        end
      end

      %w[whatsapp_cloud unoapi].each do |provider|
        it "lets a primary-only agent select #{provider} through stale secondary input" do
          agent = create(:user, account: account, role: :agent)
          create(:inbox_member, user: agent, inbox: primary)
          params[:assignee_id] = agent.id
          params[:message][:whatsapp_transport] = provider

          post endpoint, params: params, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('id'))
          expect(conversation.inbox_id).to eq(primary.id)
          expect(conversation.messages.where(message_type: :outgoing).last.content_attributes.dig('whatsapp_transport', 'provider')).to eq(provider)
        end
      end

      it 'rejects a secondary-only agent without creating messages or conversations' do
        agent = create(:user, account: account, role: :agent)
        create(:inbox_member, user: agent, inbox: secondary)
        counts = [Conversation.count, Message.count, Contact.count, ContactInbox.count]

        post endpoint, params: params, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect([Conversation.count, Message.count, Contact.count, ContactInbox.count]).to eq(counts)
      end

      it 'denies a foreign account without creating anything' do
        outsider = create(:user, account: create(:account), role: :administrator)
        counts = [Conversation.count, Message.count, ContactInbox.count]

        post endpoint, params: params, headers: outsider.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect([Conversation.count, Message.count, ContactInbox.count]).to eq(counts)
      end

      it 'reuses an existing contact for either known Brazilian source alias through direct recipient input' do
        snapshot = contact.attributes.slice('id', 'name', 'phone_number', 'additional_attributes')
        params.delete(:contact_id)
        params.delete(:source_id)
        params[:recipient] = { phone_number: '66996269251' }

        expect do
          post endpoint, params: params, headers: admin.create_new_auth_token, as: :json
          expect(response).to have_http_status(:success)
          params[:recipient][:phone_number] = '6696269251'
          post endpoint, params: params, headers: admin.create_new_auth_token, as: :json
          expect(response).to have_http_status(:success)
        end.not_to change(Contact, :count)

        expect(contact.reload.attributes.slice(*snapshot.keys)).to eq(snapshot)
        expect(contact.conversations.where(inbox: primary).count).to eq(1)
        expect(contact.contact_inboxes.count).to eq(2)
      end
    end
  end

  context 'with a Meta principal and a recipient known only by Uno LID' do
    let(:link) do
      WhatsappInboxLink.create!(account: account, primary_inbox: meta_channel.inbox, secondary_inbox: uno_channel.inbox,
                                default_provider: 'unoapi', enabled: true, meta_initial_messages_enabled: false)
    end
    let!(:lid_contact) { create(:contact, account: account, phone_number: nil, bsuid: '212721190613051@lid', name: 'LID human name') }
    let!(:uno_alias) { create(:contact_inbox, contact: lid_contact, inbox: uno_channel.inbox, source_id: lid_contact.bsuid) }
    let(:params) do
      { inbox_id: uno_channel.inbox.id, contact_id: lid_contact.id, source_id: uno_alias.source_id,
        message: { content: 'Synthetic LID message', message_type: 'outgoing', whatsapp_transport: 'unoapi' } }
    end

    before { link }

    it 'creates only the internal principal association and resolves Uno through its proven LID' do
      snapshot = lid_contact.reload.attributes.slice('id', 'name', 'phone_number', 'bsuid', 'additional_attributes')

      expect do
        post endpoint, params: params, headers: admin.create_new_auth_token, as: :json
      end.not_to change(Contact, :count)

      expect(response).to have_http_status(:success)
      conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('id'))
      message = conversation.messages.where(message_type: :outgoing).last
      transport = Whatsapp::UnifiedTransportService.new(message: message)
      aggregate_failures 'internal association versus physical recipient identity' do
        expect(conversation).to have_attributes(inbox_id: meta_channel.inbox.id, contact_id: lid_contact.id)
        expect(conversation.contact_inbox.source_id).to eq("unified-contact:#{lid_contact.id}")
        expect(transport.inbox.id).to eq(uno_channel.inbox.id)
        expect(transport.recipient).to eq(uno_alias.source_id)
      end
      expect(lid_contact.reload.attributes.slice(*snapshot.keys)).to eq(snapshot)
      expect(uno_alias.reload.source_id).to eq('212721190613051@lid')
      expect(lid_contact.contact_inboxes.count).to eq(2)
    end

    it 'supports direct LID recipient input without creating or merging contacts' do
      params.delete(:contact_id)
      params.delete(:source_id)
      params[:recipient] = { bsuid: lid_contact.bsuid }
      contact_ids = account.contacts.order(:id).pluck(:id)

      2.times do
        post endpoint, params: params, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end

      expect(account.contacts.order(:id).pluck(:id)).to eq(contact_ids)
      expect(lid_contact.conversations.where(inbox: meta_channel.inbox).count).to eq(1)
      expect(lid_contact.contact_inboxes.where(inbox: meta_channel.inbox).sole.source_id).to eq("unified-contact:#{lid_contact.id}")
      expect(uno_alias.reload.source_id).to eq(lid_contact.bsuid)
    end

    it 'fails a Meta delivery preflight without HTTP or inheriting the Uno identity' do
      params[:message][:whatsapp_transport] = 'whatsapp_cloud'
      post endpoint, params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('id'))
      # Open the synthetic reply window so the failure is recipient validation,
      # not the independent missing-template guard. No provider call is mocked.
      create(:message, account: account, inbox: meta_channel.inbox, conversation: conversation,
                       message_type: :incoming, sender: lid_contact, content: 'Synthetic incoming window')
      message = conversation.messages.where(message_type: :outgoing).last
      request_count = WebMock::RequestRegistry.instance.requested_signatures.hash.values.sum

      expect do
        Whatsapp::SendOnWhatsappService.new(message: message).perform
      end.to raise_error(ArgumentError, /Recipient identity pending/)

      expect(WebMock::RequestRegistry.instance.requested_signatures.hash.values.sum).to eq(request_count)
      aggregate_failures 'preflight failure has no external delivery attempt' do
        expect(message.reload.status).to eq('failed')
        expect(message.content_attributes.dig('whatsapp_transport', 'delivery_state')).to eq('preflight_failed')
        expect(message.content_attributes.dig('whatsapp_transport', 'delivery_attempt_id')).to be_blank
      end
      expect(message.source_id).to be_blank
      expect(uno_alias.reload.source_id).to eq('212721190613051@lid')
      expect(conversation.contact_inbox.reload.source_id).to eq("unified-contact:#{lid_contact.id}")
    end
  end
end
