require 'rails_helper'

RSpec.describe Messages::ForwardService do
  media_cases = [['sample.png', 'image/png', 'image'], ['sample.mp3', 'audio/mpeg', 'audio'], ['sample.pdf', 'application/pdf', 'file']].freeze
  provider_selections = [nil, 'unoapi', 'whatsapp_cloud'].freeze
  resumable_statuses = %w[pending snoozed].freeze

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

  before do
    Current.account = account
    Current.user = user
    create(:inbox_member, inbox: source_conversation.inbox, user: user)
    create(:inbox_member, inbox: inbox, user: user)
  end

  after { Current.reset }

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

  it 'does not export private notes' do
    source_message.update!(private: true)

    expect { service.perform }.to raise_error(ArgumentError, /Private/)
    expect(existing_conversation.reload.messages).to be_empty
  end

  it 'checks source permissions even when called outside the controller' do
    source_conversation.inbox.inbox_members.where(user: user).destroy_all

    expect { service.perform }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'checks target inbox permissions before assigning a conversation' do
    inbox.inbox_members.where(user: user).destroy_all

    expect { service.perform }.to raise_error(Pundit::NotAuthorizedError)
    expect(existing_conversation.reload.assignee_id).not_to eq(user.id)
  end

  it 'rejects an explicit provider for an unlinked destination without saving a message' do
    forwarding = described_class.new(account: account, user: user, source_messages: [source_message],
                                     target_conversation: existing_conversation, requested_provider: 'whatsapp_cloud')

    expect { forwarding.perform }.to raise_error(ArgumentError, /enabled inbox link/)
    expect(existing_conversation.reload.messages).to be_empty
  end

  it 'keeps an explicit ordinary destination and creates a fresh message for each intentional forward' do
    forwarding = described_class.new(account: account, user: user, source_messages: [source_message],
                                     target_conversation: existing_conversation)
    source_id = source_message.id
    source_message.update!(source_id: 'old-provider-id', status: :failed,
                           additional_attributes: { template_params: { name: 'old-template' } },
                           content_attributes: {
                             contacts: [{ formatted_name: 'Synthetic', phone_number: '+5565999990000' }],
                             view_once: true, whatsapp_transport: { provider: 'whatsapp_cloud' },
                             in_reply_to: 42, in_reply_to_external_id: 'old-quote', external_error: 'old-error',
                             idempotency_key: 'old-key', automation_rule_id: 12, web_absence_request_key: 'old-web',
                             whatsapp_unified_message_id: 91, external_echo: true
                           })

    2.times { expect(forwarding.perform).to eq(existing_conversation) }

    forwarded = existing_conversation.messages.order(:id).last(2)
    expect(forwarded.map(&:id).uniq.size).to eq(2)
    forwarded.each do |message|
      expect(message.content_attributes).to eq(
        'contacts' => [{ 'formatted_name' => 'Synthetic', 'phone_number' => '+5565999990000' }],
        'view_once' => true, 'forwarded_from_conversation_id' => source_conversation.id, 'forwarded_from_message_id' => source_id
      )
      expect(message).to have_attributes(sender: user, delivery_destination: 'channel', private: false, source_id: nil)
      expect(message.additional_attributes).not_to have_key('template_params')
    end
    expect(source_message.reload).to have_attributes(id: source_id, source_id: 'old-provider-id', status: 'failed')
  end

  media_cases.each do |name, mime, type|
    it "reuses the #{type} blob without downloading or uploading another object" do
      attachment = source_message.attachments.build(account: account, file_type: type, meta: { 'synthetic' => true })
      attachment.file.attach(io: File.open(Rails.root.join('spec/assets', name)), filename: name, content_type: mime)
      attachment.save!
      blob = attachment.file.blob
      expect(blob).not_to receive(:download)
      expect(ActiveStorage::Blob).not_to receive(:create_and_upload!)

      expect { service.perform }.not_to change(ActiveStorage::Blob, :count)

      forwarded = contact.conversations.order(:id).last.messages.last.attachments.last
      expect(forwarded.file.blob_id).to eq(blob.id)
      expect(forwarded.file.blob).to have_attributes(filename: blob.filename, content_type: mime, byte_size: blob.byte_size)
      expect(forwarded.meta).to eq(attachment.meta)
      expect(forwarded.id).not_to eq(attachment.id)
    end
  end

  it 'retains non-file contact and location attachments' do
    source_message.attachments.create!(account: account, file_type: :contact, fallback_title: 'Synthetic Contact',
                                       meta: { 'phone_number' => '+5565999990000' })
    source_message.attachments.create!(account: account, file_type: :location, fallback_title: 'Synthetic Location',
                                       coordinates_lat: -15.6, coordinates_long: -56.1, external_url: 'https://maps.invalid/location')

    result = service.perform

    expect(result.messages.last.attachments.map { |attachment| attachment.attributes.except('id', 'message_id', 'created_at', 'updated_at') })
      .to eq(source_message.attachments.map { |attachment| attachment.attributes.except('id', 'message_id', 'created_at', 'updated_at') })
  end

  # Both physical inboxes, aliases and conversations are required to exercise either principal.
  # rubocop:disable RSpec/MultipleMemoizedHelpers
  %w[unoapi whatsapp_cloud].each do |principal|
    context "when #{principal} is the principal of an active pair" do
      let(:meta_channel) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: channel.phone_number.delete_prefix('+'),
                                  sync_templates: false, validate_provider_config: false)
      end
      let!(:link) do
        WhatsappInboxLink.create!(account: account,
                                  primary_inbox: principal == 'unoapi' ? inbox : meta_channel.inbox,
                                  secondary_inbox: principal == 'unoapi' ? meta_channel.inbox : inbox,
                                  enabled: true, default_provider: 'whatsapp_cloud')
      end
      let!(:meta_contact_inbox) { create(:contact_inbox, inbox: meta_channel.inbox, contact: contact, source_id: '5566999535182') }
      let!(:meta_conversation) do
        create(:conversation, account: account, inbox: meta_channel.inbox, contact: contact, contact_inbox: meta_contact_inbox)
      end
      let(:primary_conversation) { principal == 'unoapi' ? existing_conversation : meta_conversation }
      let(:legacy_conversation) { principal == 'unoapi' ? meta_conversation : existing_conversation }

      before do
        create(:inbox_member, inbox: meta_channel.inbox, user: user)
        link.primary_inbox.update!(lock_to_single_conversation: true)
        create(:message, account: account, inbox: meta_channel.inbox, conversation: primary_conversation,
                         message_type: :incoming, sender: contact)
      end

      provider_selections.each do |provider|
        it "resolves a legacy secondary target and prepares #{provider || 'default'} transport before save" do
          legacy_state = legacy_conversation.reload.attributes
          original_id = source_message.id
          forwarding = described_class.new(account: account, user: user, source_messages: [source_message],
                                           target_conversation: legacy_conversation, requested_provider: provider)

          expect { expect(forwarding.perform).to eq(primary_conversation) }.not_to change(Conversation, :count)

          message = primary_conversation.messages.last
          expect(message.content_attributes['whatsapp_transport']).to include(
            'requested_provider' => provider || 'whatsapp_cloud', 'provider' => provider || 'whatsapp_cloud', 'link_id' => link.id
          )
          expect(message).to have_attributes(inbox_id: link.primary_inbox_id, sender: user, delivery_destination: 'channel')
          expect(legacy_conversation.reload.attributes).to eq(legacy_state)
          expect(source_message.reload.id).to eq(original_id)
        end
      end

      it 'does not grant primary access through secondary membership' do
        link.primary_inbox.inbox_members.where(user: user).destroy_all
        forwarding = described_class.new(account: account, user: user, source_messages: [source_message],
                                         target_conversation: legacy_conversation)

        expect { forwarding.perform }.to raise_error(Pundit::NotAuthorizedError)
        expect(primary_conversation.reload.messages.outgoing).to be_empty
      end

      it 'preserves principal staffing and leaves legacy identity/history unchanged' do
        other_agent = create(:user, account: account)
        team = create(:team, account: account)
        create(:inbox_member, inbox: link.primary_inbox, user: other_agent)
        create(:team_member, team: team, user: other_agent)
        primary_conversation.update!(assignee: other_agent, team: team)
        forwarding = described_class.new(account: account, user: user, source_messages: [source_message],
                                         target_conversation: legacy_conversation, requested_provider: 'unoapi')

        forwarding.perform

        expect(primary_conversation.reload).to have_attributes(assignee: other_agent, team: team)
        expect(legacy_conversation.reload.inbox_id).to eq(link.secondary_inbox_id)
      end

      resumable_statuses.each do |status|
        it "preserves the principal #{status} status during an intentional forward" do
          primary_conversation.update!(status: status)
          forwarding = described_class.new(account: account, user: user, source_messages: [source_message],
                                           target_conversation: primary_conversation, requested_provider: 'unoapi')

          forwarding.perform

          expect(primary_conversation.reload.status).to eq(status)
        end
      end

      it 'rejects a closed Meta window before any outgoing message or attachment is persisted' do
        primary_conversation.messages.incoming.each { |message| message.update!(created_at: 3.days.ago) }
        second_source = create(:message, account: account, inbox: source_conversation.inbox, conversation: source_conversation,
                                         content: 'Second synthetic message')
        source_message.attachments.create!(account: account, file_type: :location, coordinates_lat: 1, coordinates_long: 2)
        forwarding = described_class.new(account: account, user: user, source_messages: [source_message, second_source],
                                         target_conversation: legacy_conversation, requested_provider: 'whatsapp_cloud')
        count = [Message.count, Attachment.count, ActiveStorage::Blob.count]

        expect { forwarding.perform }.to raise_error(ArgumentError, /Meta reply window/)

        expect([Message.count, Attachment.count, ActiveStorage::Blob.count]).to eq(count)
      end

      it 'allows an outbound-only ViperConnect selection when the Meta window is closed' do
        primary_conversation.messages.incoming.each { |message| message.update!(created_at: 3.days.ago) }
        forwarding = described_class.new(account: account, user: user, source_messages: [source_message],
                                         target_conversation: legacy_conversation, requested_provider: 'unoapi')

        expect(forwarding.perform.messages.last.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
      end

      media_cases.each do |name, mime, type|
        it "keeps the same #{type} blob when forwarding to the principal" do
          attachment = source_message.attachments.build(account: account, file_type: type)
          attachment.file.attach(io: File.open(Rails.root.join('spec/assets', name)), filename: name, content_type: mime)
          attachment.save!
          forwarding = described_class.new(account: account, user: user, source_messages: [source_message],
                                           target_conversation: legacy_conversation, requested_provider: 'unoapi')

          expect { forwarding.perform }.not_to change(ActiveStorage::Blob, :count)

          expect(primary_conversation.messages.last.attachments.last.file.blob_id).to eq(attachment.file.blob_id)
        end
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
