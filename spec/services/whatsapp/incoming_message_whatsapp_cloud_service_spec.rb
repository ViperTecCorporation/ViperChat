require 'rails_helper'

describe Whatsapp::IncomingMessageWhatsappCloudService do
  describe '#perform' do
    after do
      Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
    end

    let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:params) do
      {
        phone_number: whatsapp_channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }],
              messages: [{
                from: '2423423243',
                image: {
                  id: 'b1c68f38-8734-4ad3-b4a1-ef0c10d683',
                  mime_type: 'image/jpeg',
                  sha256: '29ed500fa64eb55fc19dc4124acb300e5dcca0f822a301ae99944db',
                  caption: 'Check out my product!'
                },
                timestamp: '1664799904', type: 'image'
              }]
            }
          }]
        }]
      }.with_indifferent_access
    end

    context 'when valid attachment message params' do
      it 'creates appropriate conversations, message and contacts' do
        stub_media_url_request
        stub_sample_png_request
        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform
        expect_conversation_created
        expect_contact_name
        expect_message_content
        expect_message_has_attachment
      end

      it 'increments reauthorization count if fetching attachment fails' do
        stub_request(
          :get,
          whatsapp_channel.media_url('b1c68f38-8734-4ad3-b4a1-ef0c10d683')
        ).to_return(
          status: 401
        )

        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform
        expect(whatsapp_channel.inbox.conversations.count).not_to eq(0)
        expect(Contact.all.first.name).to eq('Sojan Jose')
        expect(whatsapp_channel.inbox.messages.first.content).to eq('Check out my product!')
        expect(whatsapp_channel.inbox.messages.first.attachments.present?).to be false
        expect(whatsapp_channel.authorization_error_count).to eq(1)
      end
    end

    context 'when invalid attachment message params' do
      let(:error_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }],
                messages: [{
                  from: '2423423243',
                  image: {
                    id: 'b1c68f38-8734-4ad3-b4a1-ef0c10d683',
                    mime_type: 'image/jpeg',
                    sha256: '29ed500fa64eb55fc19dc4124acb300e5dcca0f822a301ae99944db',
                    caption: 'Check out my product!'
                  },
                  errors: [{
                    code: 400,
                    details: 'Last error was: ServerThrottle. Http request error: HTTP response code said error. See logs for details',
                    title: 'Media download failed: Not retrying as download is not retriable at this time'
                  }],
                  timestamp: '1664799904', type: 'image'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'with attachment errors' do
        described_class.new(inbox: whatsapp_channel.inbox, params: error_params).perform
        expect(whatsapp_channel.inbox.conversations.count).not_to eq(0)
        expect(Contact.all.first.name).to eq('Sojan Jose')
        expect(whatsapp_channel.inbox.messages.count).to eq(0)
      end
    end

    context 'when invalid params' do
      it 'will not throw error' do
        described_class.new(inbox: whatsapp_channel.inbox, params: { phone_number: whatsapp_channel.phone_number,
                                                                     object: 'whatsapp_business_account', entry: {} }).perform
        expect(whatsapp_channel.inbox.conversations.count).to eq(0)
        expect(Contact.all.first).to be_nil
        expect(whatsapp_channel.inbox.messages.count).to eq(0)
      end
    end

    context 'when webhook payload contains an outgoing message' do
      let(:outgoing_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                metadata: {
                  display_phone_number: whatsapp_channel.phone_number.delete('+'),
                  phone_number_id: whatsapp_channel.provider_config['phone_number_id']
                },
                contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }],
                messages: [{
                  from: whatsapp_channel.phone_number.delete('+'),
                  id: 'wamid.OUTGOING_MESSAGE_ID',
                  text: { body: 'Mensagem enviada pelo atendimento' },
                  timestamp: '1770407829',
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'stores it as outgoing external echo without contact as sender' do
        described_class.new(inbox: whatsapp_channel.inbox, params: outgoing_params).perform

        message = whatsapp_channel.inbox.messages.last
        expect(message.message_type).to eq('outgoing')
        expect(message.sender).to be_nil
        expect(message.status).to eq('delivered')
        expect(message.content_attributes['external_echo']).to be true
      end
    end

    context 'when message is a reply (has context)' do
      let(:reply_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Pranav' }, wa_id: '16503071063' }],
                messages: [{
                  context: {
                    from: '16503071063',
                    id: 'wamid.ORIGINAL_MESSAGE_ID'
                  },
                  from: '16503071063',
                  id: 'wamid.REPLY_MESSAGE_ID',
                  timestamp: '1770407829',
                  text: { body: 'This is a reply' },
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      context 'when the original message exists in Chatwoot' do
        it 'sets in_reply_to to reference the existing message' do
          # Create a conversation and the original message that will be replied to first
          contact = create(:contact, phone_number: '+16503071063', account: whatsapp_channel.account)
          contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: '16503071063')
          conversation = create(:conversation, contact: contact, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox)

          original_message = create(:message,
                                    conversation: conversation,
                                    source_id: 'wamid.ORIGINAL_MESSAGE_ID',
                                    content: 'Original message')

          described_class.new(inbox: whatsapp_channel.inbox, params: reply_params).perform

          reply_message = whatsapp_channel.inbox.messages.find_by!(source_id: 'wamid.REPLY_MESSAGE_ID')
          expect(reply_message.content).to eq('This is a reply')
          expect(reply_message.content_attributes['in_reply_to']).to eq(original_message.id)
          expect(reply_message.content_attributes['in_reply_to_external_id']).to eq('wamid.ORIGINAL_MESSAGE_ID')
        end
      end

      context 'when the original message does not exist in Chatwoot' do
        it 'does not set in_reply_to (discards the reply reference)' do
          described_class.new(inbox: whatsapp_channel.inbox, params: reply_params).perform

          reply_message = whatsapp_channel.inbox.messages.last
          expect(reply_message.content).to eq('This is a reply')
          expect(reply_message.content_attributes['in_reply_to']).to be_nil
          expect(reply_message.content_attributes['in_reply_to_external_id']).to be_nil
        end
      end
    end

    context 'when unoapi structured group schema is enabled' do
      let!(:whatsapp_channel) do
        create(
          :channel_whatsapp,
          provider: 'unoapi',
          provider_config: {
            'api_key' => 'test_key',
            'phone_number_id' => '556600000000',
            'business_account_id' => '123456789',
            'use_group_conversation_schema' => true
          },
          sync_templates: false,
          validate_provider_config: false
        )
      end

      let(:params) do
        {
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                messaging_product: 'whatsapp',
                metadata: {
                  display_phone_number: '556600000000',
                  phone_number_id: whatsapp_channel.provider_config['phone_number_id']
                },
                contacts: [{
                  wa_id: '556699999999',
                  user_id: '123456789012345@lid',
                  profile: {
                    name: 'Maria',
                    username: '@maria.vendas',
                    picture: 'https://cdn.example.com/profile/maria.jpg'
                  },
                  group_id: '120363040468224422@g.us',
                  group_subject: 'Equipe Comercial',
                  group_picture: 'https://cdn.example.com/groups/120363040468224422.jpg'
                }],
                messages: [{
                  from: '556699999999',
                  from_user_id: '123456789012345@lid',
                  id: 'wamid.GROUP_MESSAGE_ID',
                  timestamp: '1710000000',
                  type: 'text',
                  group_id: '120363040468224422@g.us',
                  text: { body: 'Bom dia pessoal' }
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'creates a structured group conversation with the real sender' do
        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: params).perform
        end.to have_enqueued_job(Whatsapp::Unoapi::GroupParticipantsSyncJob)

        conversation = whatsapp_channel.inbox.conversations.find_by!(group_source_id: '120363040468224422@g.us')
        message = conversation.messages.last

        expect(conversation).to be_group
        expect(conversation.group_title).to eq('Equipe Comercial')
        expect(conversation.additional_attributes['group_picture']).to eq('https://cdn.example.com/groups/120363040468224422.jpg')
        expect(conversation.contact_inbox.source_id).to eq('120363040468224422@g.us')
        expect(conversation.group_contacts.count).to eq(1)
        expect(conversation.group_contacts.first.contact).to eq(message.sender)
        expect(message.sender.name).to eq('Maria')
        expect(message.sender.bsuid).to eq('123456789012345@lid')
        expect(message.sender.whatsapp_username).to eq('@maria.vendas')
        expect(conversation.group_contacts.first.metadata).to include(
          'wa_id' => '556699999999',
          'user_id' => '123456789012345@lid',
          'username' => '@maria.vendas'
        )
        expect(message.content).to eq('Bom dia pessoal')
      end

      it 'uses bsuid as the structured group sender when no valid phone is present' do
        lid_params = params.deep_dup
        contact = lid_params[:entry][0][:changes][0][:value][:contacts][0]
        message = lid_params[:entry][0][:changes][0][:value][:messages][0]
        contact[:wa_id] = '123456789012345@lid'
        message[:from] = '123456789012345@lid'
        message[:id] = 'wamid.GROUP_LID_MESSAGE_ID'

        described_class.new(inbox: whatsapp_channel.inbox, params: lid_params).perform

        conversation = whatsapp_channel.inbox.conversations.find_by!(group_source_id: '120363040468224422@g.us')
        sender = conversation.messages.find_by!(source_id: 'wamid.GROUP_LID_MESSAGE_ID').sender
        contact_inbox = sender.contact_inboxes.find_by!(inbox: whatsapp_channel.inbox)

        expect(contact_inbox.source_id).to eq('123456789012345@lid')
        expect(sender.bsuid).to eq('123456789012345@lid')
        expect(sender.phone_number).to be_nil
      end

      it 'does not enqueue participants sync again before the interval expires' do
        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform
        clear_enqueued_jobs

        conversation = whatsapp_channel.inbox.conversations.find_by!(group_source_id: '120363040468224422@g.us')
        conversation.update!(group_contacts_synced_at: 30.minutes.ago)

        next_params = params.deep_dup
        next_params[:entry][0][:changes][0][:value][:messages][0][:id] = 'wamid.GROUP_MESSAGE_ID_2'

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: next_params).perform
        end.not_to have_enqueued_job(Whatsapp::Unoapi::GroupParticipantsSyncJob)
      end

      it 'enqueues participants sync again after the interval expires' do
        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform
        clear_enqueued_jobs

        conversation = whatsapp_channel.inbox.conversations.find_by!(group_source_id: '120363040468224422@g.us')
        conversation.update!(group_contacts_synced_at: 3.hours.ago)

        next_params = params.deep_dup
        next_params[:entry][0][:changes][0][:value][:messages][0][:id] = 'wamid.GROUP_MESSAGE_ID_2'

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: next_params).perform
        end.to have_enqueued_job(Whatsapp::Unoapi::GroupParticipantsSyncJob)
      end

      it 'updates a group message status by group recipient id' do
        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform

        status_params = params.deep_dup
        status_params[:entry][0][:changes][0][:value].delete(:messages)
        status_params[:entry][0][:changes][0][:value].delete(:contacts)
        status_params[:entry][0][:changes][0][:value][:statuses] = [{
          id: 'wamid.GROUP_MESSAGE_ID',
          recipient_id: '120363040468224422@g.us',
          recipient_type: 'group',
          status: 'delivered',
          timestamp: '1710000005'
        }]

        described_class.new(inbox: whatsapp_channel.inbox, params: status_params).perform

        expect(whatsapp_channel.inbox.messages.find_by!(source_id: 'wamid.GROUP_MESSAGE_ID').status).to eq('delivered')
      end
    end
  end

  # Métodos auxiliares para reduzir o tamanho do exemplo

  def stub_media_url_request
    stub_request(
      :get,
      whatsapp_channel.media_url('b1c68f38-8734-4ad3-b4a1-ef0c10d683')
    ).to_return(
      status: 200,
      body: {
        messaging_product: 'whatsapp',
        url: 'https://chatwoot-assets.local/sample.png',
        mime_type: 'image/jpeg',
        sha256: 'sha256',
        file_size: 'SIZE',
        id: 'b1c68f38-8734-4ad3-b4a1-ef0c10d683'
      }.to_json,
      headers: { 'content-type' => 'application/json' }
    )
  end

  def stub_sample_png_request
    stub_request(:get, 'https://chatwoot-assets.local/sample.png').to_return(
      status: 200,
      body: File.read('spec/assets/sample.png')
    )
  end

  def expect_conversation_created
    expect(whatsapp_channel.inbox.conversations.count).not_to eq(0)
  end

  def expect_contact_name
    expect(Contact.all.first.name).to eq('Sojan Jose')
  end

  def expect_message_content
    expect(whatsapp_channel.inbox.messages.first.content).to eq('Check out my product!')
  end

  def expect_message_has_attachment
    expect(whatsapp_channel.inbox.messages.first.attachments.present?).to be true
  end
end
