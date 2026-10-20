require 'rails_helper'

# Run against the main agent's isolated test DB with the existing unified-inbox
# schema. Exercise both real provider entry points; do not mock ingestion,
# identity correlation, contact attachment building or persistence.
RSpec.describe Whatsapp::UnifiedMessageIngestionService do
  arrival_orders = [%i[meta uno], %i[uno meta]].freeze
  card_counts = [1, 3].freeze
  expected_cards = {
    1 => { phones: ['+5565987654321'], names: ['Primeiro Cartão'] },
    3 => { phones: ['+5565987654321', '+5511987654321', '+551132345678', 'Phone number is not available'],
           names: ['Primeiro Cartão', 'Segundo Cartão', 'Segundo Cartão', 'Sem Telefone'] }
  }.freeze
  let(:account) { create(:account) }
  let(:cards) do
    [
      { name: { formatted_name: 'Primeiro Cartão', first_name: 'Primeiro', last_name: 'Cartão' },
        phones: [{ phone: '+5565987654321', type: 'CELL' }] },
      { name: { formatted_name: 'Segundo Cartão', first_name: 'Segundo', last_name: 'Cartão' },
        phones: [{ phone: '+5511987654321', type: 'CELL' }, { phone: '+551132345678', type: 'WORK' }] },
      { name: { formatted_name: 'Sem Telefone', first_name: 'Sem', last_name: 'Telefone' } }
    ]
  end
  let(:card_count) { 3 }
  let(:event_timestamp) { Time.current.to_i.to_s }
  let(:public_messages) { account.messages.where(message_type: %i[incoming outgoing], private: false) }
  let(:meta_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno_channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              provider_config: { 'api_key' => 'synthetic', 'url' => 'https://uno.invalid' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:channels) { { meta: meta_channel, uno: uno_channel } }
  let(:external_ids) do
    { uno: 'c1e91240-c9ef-11f1-8b89-01afaf97c044',
      meta: 'wamid.HBgMNTU2Njk2MjY5MjUxFQIAEhgUM0E0NTlDQzRGMjFDN0RGNEU4QjQA' }
  end
  let(:participants) { { uno: '5566996269251', meta: '556696269251' } }
  let!(:known_contact) do
    create(:contact, account: account, name: 'Nome humano preservado', phone_number: '+5566996269251',
                     additional_attributes: { 'manual_reference' => 'keep' })
  end
  let!(:meta_alias) { create(:contact_inbox, inbox: meta_channel.inbox, contact: known_contact, source_id: participants[:meta]) }
  let!(:uno_alias) { create(:contact_inbox, inbox: uno_channel.inbox, contact: known_contact, source_id: participants[:uno]) }

  before do
    create(:contact, account: account, name: 'Cadastro humano existente', phone_number: '+5565987654321')
    # All cases must forbid media IO, including fixture setup and retries.
    # rubocop:disable RSpec/ExpectInHook
    expect(Down).not_to receive(:download)
    expect(ActiveStorage::Blob.service).not_to receive(:upload)
    expect(ActiveStorage::Blob.service).not_to receive(:delete)
    # rubocop:enable RSpec/ExpectInHook
  end

  around do |example|
    previous_network_configuration = WebMock::Config.instance.allow_net_connect
    previous_localhost_configuration = WebMock::Config.instance.allow_localhost
    WebMock.disable_net_connect!(allow_localhost: false)
    travel_to(Time.at(1_792_151_940).utc) { example.run }
  ensure
    WebMock::Config.instance.allow_net_connect = previous_network_configuration
    WebMock::Config.instance.allow_localhost = previous_localhost_configuration
  end

  # These helpers share only the provider envelope and dispatch. All domain
  # setup, retries and assertions stay in the examples.
  def webhook(provider)
    channel = channels.fetch(provider)
    message = {
      id: external_ids.fetch(provider), from: participants.fetch(provider), timestamp: event_timestamp,
      type: 'contacts', contacts: cards.first(card_count)
    }
    message[:provider_message_id] = '3A459CC4F21C7DF4E8B4' if provider == :uno
    {
      object: 'whatsapp_business_account', phone_number: channel.phone_number,
      entry: [{ id: '200000000000000', changes: [{ field: 'messages', value: {
        messaging_product: 'whatsapp',
        metadata: { display_phone_number: channel.phone_number.delete_prefix('+'),
                    phone_number_id: channel.provider_config['phone_number_id'] },
        contacts: [{ wa_id: participants.fetch(provider), profile: { name: 'Nome humano preservado' } }],
        messages: [message]
      } }] }]
    }.with_indifferent_access
  end

  def ingest(provider, payload = webhook(provider))
    service = provider == :meta ? Whatsapp::IncomingMessageWhatsappCloudService : Whatsapp::IncomingMessageUnoapiService
    service.new(inbox: channels.fetch(provider).inbox, params: payload.deep_dup).perform
  end

  %i[meta uno].each do |principal|
    context "with #{principal} as principal" do
      let!(:inbox_link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                  secondary_inbox: channels.fetch(principal == :meta ? :uno : :meta).inbox,
                                  default_provider: 'whatsapp_cloud', enabled: true, activated_at: 1.day.ago)
      end

      arrival_orders.each do |arrival_order|
        card_counts.each do |size|
          context "with #{size} cards arriving #{arrival_order.join(' then ')}" do
            let(:card_count) { size }

            it 'keeps one canonical bubble, every card and all existing public IDs through retries', :aggregate_failures do
              allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
              contact_keys = %w[id name phone_number additional_attributes created_at]
              contacts_before = account.contacts.order(:id).map { |contact| contact.attributes.slice(*contact_keys) }
              blob_count = ActiveStorage::Blob.count
              storage_attachment_count = ActiveStorage::Attachment.count
              attachment_count = Attachment.count

              ingest(arrival_order.first)
              canonical = public_messages.sole
              conversation = canonical.conversation
              message_snapshot = canonical.attributes.slice('id', 'source_id', 'content', 'created_at', 'conversation_id', 'inbox_id')
              attachment_snapshots = canonical.attachments.order(:id).map(&:attributes)
              ingest(arrival_order.last)
              2.times { arrival_order.reverse_each { |provider| ingest(provider) } }

              expect(public_messages.reload.pluck(:id)).to eq([canonical.id])
              expect(account.conversations.pluck(:id)).to eq([conversation.id])
              expect(canonical.reload.attributes.slice(*message_snapshot.keys)).to eq(message_snapshot)
              expect(canonical.source_id).to eq(external_ids.fetch(arrival_order.first))
              expect(canonical.inbox_id).to eq(channels.fetch(principal).inbox.id)
              expect(canonical.sender_id).to eq(known_contact.id)
              expect(conversation.contact_id).to eq(known_contact.id)
              expect(canonical.content).to eq('Primeiro Cartão')
              expect(canonical.attachments.order(:id).map(&:attributes)).to eq(attachment_snapshots)
              expected_phones = expected_cards.fetch(size).fetch(:phones)
              expected_names = expected_cards.fetch(size).fetch(:names)
              expect(canonical.attachments.order(:id).pluck(:fallback_title)).to eq(expected_phones)
              expect(canonical.attachments.order(:id).map { |attachment| attachment.meta['formattedName'] }).to eq(expected_names)
              serialized_cards = canonical.attachments.order(:id).map(&:push_event_data)
              expect(serialized_cards.map { |card| card[:meta]['formattedName'] }).to eq(expected_names)
              expect(serialized_cards.map { |card| card[:fallback_title] }).to eq(expected_phones)
              expect(canonical.attachments.pluck(:file_type).uniq).to eq(['contact'])
              expect(Attachment.count - attachment_count).to eq(expected_phones.size)
              expect(ActiveStorage::Blob.count).to eq(blob_count)
              expect(ActiveStorage::Attachment.count).to eq(storage_attachment_count)
              expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
              expect(account.contacts.order(:id).map { |contact| contact.attributes.slice(*contact_keys) }).to eq(contacts_before)
              expect(meta_alias.reload.source_id).to eq(participants[:meta])
              expect(uno_alias.reload.source_id).to eq(participants[:uno])
              expect(Rails.configuration.dispatcher).to have_received(:dispatch)
                .with('message.created', anything, hash_including(message: canonical)).once

              ledger = WhatsappUnifiedMessage.find_by!(message: canonical)
              expect(ledger).to have_attributes(original_id: '3A459CC4F21C7DF4E8B4', message_kind: 'contacts', state: 'ready')
              channels.each do |provider, channel|
                identity = WhatsappMessageIdentity.find_by!(inbox: channel.inbox, external_id: external_ids.fetch(provider))
                expect(identity.provider_message_id).to eq('3A459CC4F21C7DF4E8B4')
                alias_row = WhatsappUnifiedMessageAlias.find_by!(whatsapp_message_identity: identity)
                expect(alias_row.whatsapp_unified_message_id).to eq(ledger.id)
              end
            end
          end
        end
      end

      it 'recovers the complete multi-card bubble after losing the final ledger update' do
        ingest(:uno)
        canonical = public_messages.sole
        attachments_before = canonical.attachments.order(:id).map(&:attributes)
        ledger = WhatsappUnifiedMessage.find_by!(message: canonical)
        ledger.update!(message: nil, state: 'processing', lease_token: 'expired-worker', lease_expires_at: 1.minute.ago)

        ingest(:meta)
        ingest(:uno)

        expect(public_messages.reload.pluck(:id)).to eq([canonical.id])
        expect(ledger.reload).to have_attributes(message_id: canonical.id, state: 'ready')
        expect(canonical.attachments.order(:id).map(&:attributes)).to eq(attachments_before)
      end

      it 'leaves delayed pre-activation contact events on the legacy path' do
        %i[meta uno].each do |provider|
          payload = webhook(provider)
          payload.dig(:entry, 0, :changes, 0, :value, :messages).first[:timestamp] = 2.days.ago.to_i.to_s
          ingest(provider, payload)
        end

        expect(public_messages.count).to eq(6)
        expect(WhatsappUnifiedMessage.where(whatsapp_inbox_link: inbox_link)).to be_empty
        expect(public_messages.order(:id).map { |message| message.attachments.count }).to eq([1, 2, 1, 1, 2, 1])
      end

      it 'does not rewrite or remove historical legacy cards when ingesting new shared contacts' do
        historical_conversation = create(:conversation, account: account, inbox: uno_channel.inbox,
                                                        contact: known_contact, contact_inbox: uno_alias)
        old_cards = cards.first(2).map do |card|
          message = create(:message, account: account, inbox: uno_channel.inbox, conversation: historical_conversation,
                                     sender: known_contact, source_id: 'old-shared-contact-public-id',
                                     content: card[:name][:formatted_name], created_at: 2.days.ago)
          card[:phones].each do |phone|
            message.attachments.create!(account: account, file_type: :contact,
                                        fallback_title: phone[:phone], meta: { formattedName: card[:name][:formatted_name] })
          end
          message
        end
        message_snapshots = old_cards.index_with(&:attributes)
        attachment_snapshots = old_cards.flat_map { |message| message.attachments.map(&:attributes) }

        ingest(:meta)
        ingest(:uno)

        message_snapshots.each { |message, snapshot| expect(message.reload.attributes).to eq(snapshot) }
        expect(old_cards.flat_map { |message| message.attachments.reload.map(&:attributes) }).to eq(attachment_snapshots)
        expect(public_messages.count).to eq(old_cards.size + 1)
      end
    end
  end

  context 'without active unified ingestion' do
    [false, true].each do |disabled_link|
      it "preserves one legacy bubble per card #{disabled_link ? 'with a disabled link' : 'without a link'}" do
        if disabled_link
          WhatsappInboxLink.create!(account: account, primary_inbox: meta_channel.inbox, secondary_inbox: uno_channel.inbox,
                                    default_provider: 'whatsapp_cloud', enabled: false)
        end

        2.times { channels.each_key { |provider| ingest(provider) } }

        expect(public_messages.count).to eq(6)
        channels.each do |provider, channel|
          messages = public_messages.where(inbox: channel.inbox).order(:id)
          expect(messages.pluck(:source_id)).to eq([external_ids.fetch(provider)] * 3)
          expect(messages.pluck(:content)).to eq(cards.map { |card| card[:name][:formatted_name] })
          expect(messages.map { |message| message.attachments.count }).to eq([1, 2, 1])
        end
        expect(WhatsappUnifiedMessage.where(whatsapp_inbox_link: WhatsappInboxLink.where(account: account))).to be_empty
      end
    end
  end
end
