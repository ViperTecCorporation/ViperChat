require 'rails_helper'
require 'securerandom'

describe Whatsapp::IncomingMessageWhatsappCloudService do
  describe '#perform' do
    after do
      Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
    end

    let!(:whatsapp_channel) do
      create(
        :channel_whatsapp,
        phone_number: "+1555#{SecureRandom.random_number(10**10).to_s.rjust(10, '0')}",
        provider: 'whatsapp_cloud',
        provider_config: { 'api_key' => 'test_key', 'phone_number_id' => "random_id_#{SecureRandom.hex(4)}" },
        sync_templates: false,
        validate_provider_config: false
      )
    end
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

      it 'syncs contact avatar when a status webhook includes profile picture' do
        status_params = {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                messaging_product: 'whatsapp',
                metadata: {
                  display_phone_number: whatsapp_channel.phone_number.delete('+'),
                  phone_number_id: whatsapp_channel.provider_config['phone_number_id']
                },
                messages: [],
                contacts: [{
                  profile: {
                    name: 'Sojan Jose',
                    picture: 'https://cdn.example.com/profile/sojan.jpg',
                    picture_metadata: {
                      etag: '"avatar-etag"',
                      content_length: '41053',
                      content_type: 'image/jpeg',
                      last_modified: '2026-06-15T19:24:29.000Z'
                    }
                  },
                  wa_id: '2423423243'
                }],
                statuses: [{
                  id: 'wamid.STATUS_ONLY',
                  recipient_id: '2423423243',
                  status: 'read'
                }]
              }
            }]
          }]
        }.with_indifferent_access

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: status_params).perform
        end.to have_enqueued_job(Avatar::AvatarFromUrlJob).with(
          instance_of(Contact),
          'https://cdn.example.com/profile/sojan.jpg',
          {
            'content_length' => '41053',
            'content_type' => 'image/jpeg',
            'etag' => '"avatar-etag"',
            'last_modified' => '2026-06-15T19:24:29.000Z'
          }
        )
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

    context 'when BSUID identifiers are present' do
      it 'creates a contact and conversation when only BSUID is present' do
        bsuid_params = {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{
                  profile: { name: 'Muhsin', username: 'muhsin' },
                  user_id: 'IN.2081978709342942',
                  parent_user_id: 'IN.ENT.9081726354'
                }],
                messages: [{
                  from_user_id: 'IN.2081978709342942',
                  from_parent_user_id: 'IN.ENT.9081726354',
                  id: 'wamid.cloud-bsuid-only-message',
                  text: { body: 'testing bsuid' },
                  timestamp: '1778579582',
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access

        described_class.new(inbox: whatsapp_channel.inbox, params: bsuid_params).perform

        contact_inbox = whatsapp_channel.inbox.contact_inboxes.find_by!(source_id: 'IN.2081978709342942')
        contact = contact_inbox.contact
        parent_contact_inbox = whatsapp_channel.inbox.contact_inboxes.find_by!(source_id: 'IN.ENT.9081726354')

        expect(whatsapp_channel.inbox.conversations.count).to eq(1)
        expect(whatsapp_channel.inbox.messages.first.content).to eq('testing bsuid')
        expect(contact).to have_attributes(name: 'Muhsin', phone_number: nil)
        expect(contact.additional_attributes).to include(
          'social_whatsapp_user_name' => 'muhsin',
          'social_profiles' => { 'whatsapp' => 'muhsin' }
        )
        expect(parent_contact_inbox.contact).to eq(contact)
      end

      it 'links phone and BSUID source ids to the same contact' do
        phone_with_bsuid_params = {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Muhsin' }, wa_id: '919745786257', user_id: 'IN.2081978709342942' }],
                messages: [{
                  from: '919745786257',
                  from_user_id: 'IN.2081978709342942',
                  id: 'wamid.cloud-phone-bsuid-message',
                  text: { body: 'phone and bsuid' },
                  timestamp: '1778579582',
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access
        bsuid_only_params = {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Muhsin' }, user_id: 'IN.2081978709342942' }],
                messages: [{
                  from_user_id: 'IN.2081978709342942',
                  id: 'wamid.cloud-bsuid-follow-up-message',
                  text: { body: 'bsuid only' },
                  timestamp: '1778579583',
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access

        described_class.new(inbox: whatsapp_channel.inbox, params: phone_with_bsuid_params).perform
        contact_inbox = whatsapp_channel.inbox.contact_inboxes.find_by!(source_id: '919745786257')
        bsuid_contact_inbox = whatsapp_channel.inbox.contact_inboxes.find_by!(source_id: 'IN.2081978709342942')

        expect { described_class.new(inbox: whatsapp_channel.inbox, params: bsuid_only_params).perform }.not_to raise_error
        expect(whatsapp_channel.inbox.contact_inboxes.count).to eq(2)
        expect(whatsapp_channel.inbox.messages.pluck(:content)).to contain_exactly('phone and bsuid', 'bsuid only')
        expect(bsuid_contact_inbox.contact).to eq(contact_inbox.contact)
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

    context 'when unoapi one-to-one payload has phone and bsuid contacts' do
      let!(:whatsapp_channel) do
        create(
          :channel_whatsapp,
          provider: 'unoapi',
          provider_config: {
            'api_key' => 'test_key',
            'phone_number_id' => '556600000000',
            'business_account_id' => '123456789'
          },
          sync_templates: false,
          validate_provider_config: false
        )
      end

      let(:one_to_one_params) do
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
                  wa_id: '5566999999999',
                  user_id: '123456789012345@lid',
                  profile: { name: 'Maria', username: '@maria.vendas' }
                }],
                messages: [{
                  from: '5566999999999',
                  from_user_id: '123456789012345@lid',
                  id: 'wamid.ONE_TO_ONE_MESSAGE_ID',
                  timestamp: '1710000000',
                  type: 'text',
                  text: { body: 'Oi' }
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'merges the bsuid contact into the phone contact before processing' do
        phone_contact = create(:contact, account: whatsapp_channel.account, name: 'Contato telefone')
        phone_contact.update_columns(phone_number: '+5566999999999', email: '5566999999999') # rubocop:disable Rails/SkipsModelValidations
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: phone_contact, source_id: '5566999999999')

        bsuid_contact = create(:contact, account: whatsapp_channel.account, bsuid: '123456789012345@lid')
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: bsuid_contact, source_id: '123456789012345@lid')

        described_class.new(inbox: whatsapp_channel.inbox, params: one_to_one_params).perform

        message = whatsapp_channel.inbox.messages.find_by!(source_id: 'wamid.ONE_TO_ONE_MESSAGE_ID')
        expect(message.sender).to eq(phone_contact)
        expect(message.sender.bsuid).to eq('123456789012345@lid')
        expect(message.sender.email).to be_nil
        expect(Contact.exists?(bsuid_contact.id)).to be(false)
        expect(message.sender.contact_inboxes.find_by!(inbox: whatsapp_channel.inbox, source_id: '123456789012345@lid')).to be_present
      end

      it 'clears invalid legacy email from the bsuid contact before merging' do
        phone_contact = create(:contact, account: whatsapp_channel.account, name: 'Contato telefone')
        phone_contact.update_columns(phone_number: '+5566999999999') # rubocop:disable Rails/SkipsModelValidations
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: phone_contact, source_id: '5566999999999')

        bsuid_contact = create(:contact, account: whatsapp_channel.account, bsuid: '123456789012345@lid')
        bsuid_contact.update_columns(email: '123456789012345') # rubocop:disable Rails/SkipsModelValidations
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: bsuid_contact, source_id: '123456789012345@lid')

        expect { described_class.new(inbox: whatsapp_channel.inbox, params: one_to_one_params).perform }.not_to raise_error

        message = whatsapp_channel.inbox.messages.find_by!(source_id: 'wamid.ONE_TO_ONE_MESSAGE_ID')
        expect(message.sender).to eq(phone_contact)
        expect(message.sender.email).to be_nil
        expect(message.sender.bsuid).to eq('123456789012345@lid')
        expect(Contact.exists?(bsuid_contact.id)).to be(false)
      end

      it 'uses the existing phone conversation when the incoming message is identified by bsuid' do
        phone_contact = create(:contact, account: whatsapp_channel.account, name: 'Maria')
        phone_contact.update_columns(phone_number: '+5566999999999', bsuid: '123456789012345@lid') # rubocop:disable Rails/SkipsModelValidations
        phone_contact_inbox = create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: phone_contact, source_id: '5566999999999')
        existing_conversation = create(
          :conversation,
          account: whatsapp_channel.account,
          inbox: whatsapp_channel.inbox,
          contact: phone_contact,
          contact_inbox: phone_contact_inbox
        )

        one_to_one_params[:entry].first[:changes].first[:value][:contacts].first[:wa_id] = '123456789012345@lid'
        one_to_one_params[:entry].first[:changes].first[:value][:messages].first[:from] = '123456789012345@lid'

        described_class.new(inbox: whatsapp_channel.inbox, params: one_to_one_params).perform

        message = whatsapp_channel.inbox.messages.find_by!(source_id: 'wamid.ONE_TO_ONE_MESSAGE_ID')
        expect(message.conversation).to eq(existing_conversation)
        expect(message.sender).to eq(phone_contact)
        expect(whatsapp_channel.inbox.conversations.count).to eq(1)
        expect(phone_contact.contact_inboxes.find_by!(inbox: whatsapp_channel.inbox, source_id: '123456789012345@lid')).to be_present
      end

      it 'creates a new conversation when bsuid contact has only a resolved conversation and single conversation lock is disabled' do
        bsuid_contact = create(:contact, account: whatsapp_channel.account, name: 'Maria', bsuid: '123456789012345@lid')
        bsuid_contact_inbox = create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: bsuid_contact, source_id: '123456789012345@lid')
        existing_conversation = create(
          :conversation,
          account: whatsapp_channel.account,
          inbox: whatsapp_channel.inbox,
          contact: bsuid_contact,
          contact_inbox: bsuid_contact_inbox,
          status: :resolved
        )

        described_class.new(inbox: whatsapp_channel.inbox, params: one_to_one_params).perform

        message = whatsapp_channel.inbox.messages.find_by!(source_id: 'wamid.ONE_TO_ONE_MESSAGE_ID')
        expect(message.conversation).not_to eq(existing_conversation)
        expect(message.conversation).to be_open
        expect(message.sender).to eq(bsuid_contact)
        expect(message.sender.reload.phone_number).to eq('+5566999999999')
        expect(whatsapp_channel.inbox.conversations.count).to eq(2)
        expect(bsuid_contact.contact_inboxes.find_by!(inbox: whatsapp_channel.inbox, source_id: '5566999999999')).to be_present
      end

      it 'merges existing phone and bsuid conversations for the same UnoAPI contact when the inbox keeps a single conversation' do
        whatsapp_channel.inbox.update!(lock_to_single_conversation: true)
        phone_contact = create(:contact, account: whatsapp_channel.account, name: 'Maria')
        phone_contact.update_columns(phone_number: '+5566999999999', bsuid: '123456789012345@lid') # rubocop:disable Rails/SkipsModelValidations
        phone_contact_inbox = create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: phone_contact, source_id: '5566999999999')
        bsuid_contact_inbox = create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: phone_contact, source_id: '123456789012345@lid')
        phone_conversation = create(
          :conversation,
          account: whatsapp_channel.account,
          inbox: whatsapp_channel.inbox,
          contact: phone_contact,
          contact_inbox: phone_contact_inbox,
          last_activity_at: 2.days.ago
        )
        bsuid_conversation = create(
          :conversation,
          account: whatsapp_channel.account,
          inbox: whatsapp_channel.inbox,
          contact: phone_contact,
          contact_inbox: bsuid_contact_inbox,
          last_activity_at: 1.day.ago
        )
        old_bsuid_message = create(:message, account: whatsapp_channel.account, inbox: whatsapp_channel.inbox,
                                             conversation: bsuid_conversation, sender: phone_contact)

        one_to_one_params[:entry].first[:changes].first[:value][:contacts].first[:wa_id] = '123456789012345@lid'
        one_to_one_params[:entry].first[:changes].first[:value][:messages].first[:from] = '123456789012345@lid'

        described_class.new(inbox: whatsapp_channel.inbox, params: one_to_one_params).perform

        message = whatsapp_channel.inbox.messages.find_by!(source_id: 'wamid.ONE_TO_ONE_MESSAGE_ID')
        expect(message.conversation).to eq(phone_conversation)
        expect(old_bsuid_message.reload.conversation).to eq(phone_conversation)
        expect(Conversation.exists?(bsuid_conversation.id)).to be(false)
        expect(whatsapp_channel.inbox.conversations.where(contact: phone_contact).count).to eq(1)
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

    context 'when unoapi sends a WhatsApp message edit event' do
      let(:original_source_id) { 'wamid.ORIGINAL_MESSAGE_ID' }
      let(:edit_event_id) { 'wamid.EDIT_EVENT_ID' }
      let(:contact_wa_id) { "1650#{SecureRandom.random_number(10**7).to_s.rjust(7, '0')}" }
      let(:edited_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Pranav' }, wa_id: contact_wa_id }],
                messages: [{
                  context: {
                    id: original_source_id,
                    message_id: original_source_id
                  },
                  from: contact_wa_id,
                  id: edit_event_id,
                  message_type: 'message_edit',
                  timestamp: '1770407829',
                  edit_timestamp: '1770407830000',
                  text: { body: 'Edited message body' },
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'updates the original message instead of creating a duplicate' do
        contact = create(:contact, phone_number: "+#{contact_wa_id}", account: whatsapp_channel.account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: contact_wa_id)
        conversation = create(:conversation, contact: contact, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox)
        original_message = create(
          :message,
          conversation: conversation,
          inbox: whatsapp_channel.inbox,
          source_id: original_source_id,
          content: 'Original message body',
          content_attributes: { 'existing' => true }
        )

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: edited_params).perform
        end.not_to change(whatsapp_channel.inbox.messages, :count)

        original_message.reload
        expect(original_message.content).to eq('Edited message body')
        expect(original_message.content_attributes['edited']).to be true
        expect(original_message.content_attributes['edit_event_id']).to eq(edit_event_id)
        expect(original_message.content_attributes['edit_timestamp']).to eq('1770407830000')
        expect(original_message.content_attributes['previous_content']).to eq('Original message body')
        expect(original_message.content_attributes['existing']).to be true
      end

      it 'ignores the edit event when the edited original message is missing' do
        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: edited_params).perform
        end.not_to change(whatsapp_channel.inbox.messages, :count)
      end

      it 'recovers the original message from the recent conversation when the provider id is not mapped yet' do
        contact = create(:contact, phone_number: "+#{contact_wa_id}", account: whatsapp_channel.account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: contact_wa_id)
        conversation = create(:conversation, contact: contact, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox)
        original_message = create(
          :message,
          conversation: conversation,
          inbox: whatsapp_channel.inbox,
          source_id: 'unoapi.ORIGINAL_MESSAGE_ID',
          content: 'Original message body',
          message_type: :incoming,
          created_at: Time.zone.at(1_770_407_829)
        )

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: edited_params).perform
        end.not_to change(whatsapp_channel.inbox.messages, :count)

        original_message.reload
        expect(original_message.content).to eq('Edited message body')
        expect(original_message.content_attributes['edited']).to be true
        expect(original_message.content_attributes['edit_event_id']).to eq(edit_event_id)
        expect(original_message.content_attributes['previous_content']).to eq('Original message body')
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
                  wa_id: '5566999999999',
                  user_id: '123456789012345@lid',
                  profile: {
                    name: 'Maria',
                    username: '@maria.vendas',
                    picture: 'https://cdn.example.com/profile/maria.jpg',
                    picture_metadata: {
                      etag: '"sender-etag"',
                      content_length: '12345',
                      content_type: 'image/jpeg',
                      last_modified: '2026-06-15T19:24:29.000Z'
                    }
                  },
                  group_id: '120363040468224422@g.us',
                  group_subject: 'Equipe Comercial',
                  group_picture: 'https://cdn.example.com/groups/120363040468224422.jpg',
                  group_picture_metadata: {
                    etag: '"group-etag"',
                    content_length: '41053',
                    content_type: 'image/jpeg',
                    last_modified: '2026-06-15T19:24:29.000Z'
                  }
                }],
                messages: [{
                  from: '5566999999999',
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
          'wa_id' => '5566999999999',
          'user_id' => '123456789012345@lid',
          'username' => '@maria.vendas'
        )
        expect(message.content).to eq('Bom dia pessoal')
      end

      it 'preserves the existing group picture when a structured webhook sends an empty picture' do
        group_contact = create(:contact, account: whatsapp_channel.account, name: 'Equipe Comercial')
        group_contact_inbox = create(
          :contact_inbox,
          inbox: whatsapp_channel.inbox,
          contact: group_contact,
          source_id: '120363040468224422@g.us'
        )
        conversation = create(
          :conversation,
          account: whatsapp_channel.account,
          inbox: whatsapp_channel.inbox,
          contact: group_contact,
          contact_inbox: group_contact_inbox,
          group: true,
          group_source_id: '120363040468224422@g.us',
          group_title: 'Equipe Comercial',
          additional_attributes: { 'group_picture' => 'https://cdn.example.com/groups/current.jpg' }
        )
        empty_picture_params = params.deep_dup
        empty_picture_params[:entry][0][:changes][0][:value][:contacts][0][:group_picture] = ''
        empty_picture_params[:entry][0][:changes][0][:value][:contacts][0][:profile][:picture] = ''

        described_class.new(inbox: whatsapp_channel.inbox, params: empty_picture_params).perform

        expect(conversation.reload.additional_attributes['group_picture']).to eq('https://cdn.example.com/groups/current.jpg')
        expect(group_contact.reload.avatar_url).to be_blank
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

      it 'merges stale phone and bsuid contacts before processing structured group sender' do
        phone_contact = create(:contact, account: whatsapp_channel.account, name: 'Contato telefone')
        phone_contact.update_columns(phone_number: '+5566999999999', email: '5566999999999') # rubocop:disable Rails/SkipsModelValidations
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: phone_contact, source_id: '5566999999999')

        bsuid_contact = create(:contact, account: whatsapp_channel.account, bsuid: '123456789012345@lid')

        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform

        message = whatsapp_channel.inbox.messages.find_by!(source_id: 'wamid.GROUP_MESSAGE_ID')
        expect(message.sender).to eq(phone_contact)
        expect(message.sender.bsuid).to eq('123456789012345@lid')
        expect(message.sender.email).to be_nil
        expect(Contact.exists?(bsuid_contact.id)).to be(false)
        expect(message.sender.contact_inboxes.find_by!(inbox: whatsapp_channel.inbox, source_id: '123456789012345@lid')).to be_present
      end

      it 'merges a stale lid contact inbox into the phone contact before processing structured group sender' do
        phone_contact = create(:contact, account: whatsapp_channel.account, name: 'Contato telefone')
        phone_contact.update_columns(phone_number: '+5566999999999', bsuid: '123456789012345@lid') # rubocop:disable Rails/SkipsModelValidations
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: phone_contact, source_id: '5566999999999')

        stale_lid_contact = create(:contact, account: whatsapp_channel.account, name: 'Contato orfao')
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: stale_lid_contact, source_id: '123456789012345@lid')

        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform

        message = whatsapp_channel.inbox.messages.find_by!(source_id: 'wamid.GROUP_MESSAGE_ID')
        expect(message.sender).to eq(phone_contact)
        expect(message.sender.bsuid).to eq('123456789012345@lid')
        expect(Contact.exists?(stale_lid_contact.id)).to be(false)
        expect(message.sender.contact_inboxes.find_by!(inbox: whatsapp_channel.inbox, source_id: '123456789012345@lid')).to be_present
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

      it 'updates local group details from group settings webhooks' do
        group_contact = create(:contact, account: whatsapp_channel.account, name: 'Equipe Comercial')
        group_contact_inbox = create(
          :contact_inbox,
          inbox: whatsapp_channel.inbox,
          contact: group_contact,
          source_id: '120363040468224422@g.us'
        )
        conversation = create(
          :conversation,
          account: whatsapp_channel.account,
          inbox: whatsapp_channel.inbox,
          contact: group_contact,
          contact_inbox: group_contact_inbox,
          group: true,
          group_source_id: '120363040468224422@g.us',
          group_title: 'Equipe Comercial',
          group_description: 'Descricao antiga'
        )

        settings_params = {
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              field: 'group_settings_update',
              value: {
                group_id: '120363040468224422@g.us',
                changes: {
                  subject: 'Equipe Comercial VIP',
                  description: 'Descricao atualizada',
                  picture: 'https://cdn.example.com/groups/new-picture.jpg'
                }
              }
            }]
          }]
        }.with_indifferent_access

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: settings_params).perform
        end.to have_enqueued_job(Avatar::AvatarFromUrlJob).with(group_contact, 'https://cdn.example.com/groups/new-picture.jpg')

        expect(conversation.reload.group_title).to eq('Equipe Comercial VIP')
        expect(conversation.group_description).to eq('Descricao atualizada')
        expect(conversation.additional_attributes['group_picture']).to eq('https://cdn.example.com/groups/new-picture.jpg')
        expect(group_contact.reload.name).to eq('Equipe Comercial VIP')
      end

      it 'does not enqueue group avatar sync when group settings picture hash is unchanged' do
        picture_url = 'https://cdn.example.com/groups/new-picture.jpg'
        group_contact = create(
          :contact,
          account: whatsapp_channel.account,
          name: 'Equipe Comercial',
          additional_attributes: { 'avatar_url_hash' => Digest::SHA256.hexdigest(picture_url) }
        )
        group_contact_inbox = create(
          :contact_inbox,
          inbox: whatsapp_channel.inbox,
          contact: group_contact,
          source_id: '120363040468224422@g.us'
        )
        create(
          :conversation,
          account: whatsapp_channel.account,
          inbox: whatsapp_channel.inbox,
          contact: group_contact,
          contact_inbox: group_contact_inbox,
          group: true,
          group_source_id: '120363040468224422@g.us',
          group_title: 'Equipe Comercial'
        )

        settings_params = {
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              field: 'group_settings_update',
              value: {
                group_id: '120363040468224422@g.us',
                changes: {
                  picture: picture_url
                }
              }
            }]
          }]
        }.with_indifferent_access

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: settings_params).perform
        end.not_to have_enqueued_job(Avatar::AvatarFromUrlJob)
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
