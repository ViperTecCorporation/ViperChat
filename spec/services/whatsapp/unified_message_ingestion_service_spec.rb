require 'rails_helper'
require 'base64'
require 'stringio'
require 'tmpdir'

# Integration contract: enter through the real provider services, not a mocked
# UnifiedMessageIngestionService. Run only with an isolated test DB, including
# migrations 20261016000000, 20261016000001 and 20261016000002 and the inbox-link migration.
# Provider instances are created/reloaded inside the real pipeline. Instrument
# only the download/lookup boundary, leaving ingestion and persistence real.
# rubocop:disable RSpec/AnyInstance
RSpec.describe Whatsapp::UnifiedMessageIngestionService do
  directions = %w[incoming echo].freeze
  attempting_states = %w[attempting uncertain].freeze
  let(:account) { create(:account) }
  let(:business_suffix) { SecureRandom.random_number(10**7).to_s.rjust(7, '0') }
  let(:meta_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: "+55659#{business_suffix}",
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno_channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: "+556599#{business_suffix}",
                              provider_config: { 'api_key' => 'synthetic', 'url' => 'https://uno.invalid' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:channels) { { meta: meta_channel, uno: uno_channel } }
  let!(:known_contact) do
    create(:contact, account: account, name: 'Nome humano preservado', phone_number: '+5565987654321',
                     bsuid: '123456789012345@lid', additional_attributes: { 'manual_reference' => 'keep' })
  end
  let!(:meta_alias) { create(:contact_inbox, inbox: meta_channel.inbox, contact: known_contact, source_id: '556587654321') }
  let!(:uno_alias) { create(:contact_inbox, inbox: uno_channel.inbox, contact: known_contact, source_id: '5565987654321') }
  let(:public_messages) { account.messages.where(message_type: %i[incoming outgoing]) }

  around do |example|
    previous_network_configuration = WebMock::Config.instance.allow_net_connect
    previous_localhost_configuration = WebMock::Config.instance.allow_localhost
    WebMock.disable_net_connect!(allow_localhost: false)
    travel_to(Time.at(1_792_151_940).utc) { example.run }
  ensure
    WebMock::Config.instance.allow_net_connect = previous_network_configuration
    WebMock::Config.instance.allow_localhost = previous_localhost_configuration
  end

  # The two helpers remove repeated envelope extraction and provider dispatch,
  # while leaving each example's mutations and domain assertions visible.
  def webhook(provider, name)
    payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence', "#{provider}_#{name}.json").read).with_indifferent_access
    channel = channels.fetch(provider)
    value = payload[:entry].first[:changes].first[:value]
    business_number = channel.phone_number.delete_prefix('+')
    value[:metadata].merge!(display_phone_number: business_number, phone_number_id: channel.provider_config['phone_number_id'])
    # Echo sender is the business; to/to_user_id and the wamid participant remain
    # the fixture's peer identity, including its original 8/9-digit or BSUID form.
    Array(value[:message_echoes]).each { |echo| echo[:from] = business_number }
    payload[:phone_number] = channel.phone_number
    payload
  end

  def ingest(provider, payload)
    service = provider == :meta ? Whatsapp::IncomingMessageWhatsappCloudService : Whatsapp::IncomingMessageUnoapiService
    echo = payload.dig(:entry, 0, :changes, 0, :field) == 'smb_message_echoes'
    service.new(inbox: channels.fetch(provider).inbox, params: payload, outgoing_echo: echo).perform
  end

  def stub_media_downloads(media, urls, downloads)
    urls.each do |download_url|
      allow(Down).to receive(:download).with(download_url, headers: anything) do |url|
        downloads << url
        StringIO.new(media[:bytes]).tap do |io|
          io.define_singleton_method(:original_filename) { media[:filename] }
          io.define_singleton_method(:content_type) { media[:mime_type] }
        end
      end
    end
  end

  def delivered_receipt(payload)
    receipt = payload.deep_dup
    value = receipt.dig(:entry, 0, :changes, 0, :value)
    incoming = value.delete(:messages).first
    value[:statuses] = [{ id: incoming[:id], provider_message_id: incoming[:provider_message_id],
                          recipient_id: '5565987654321', status: 'delivered', timestamp: incoming[:timestamp] }]
    receipt
  end

  arrival_orders = [%i[meta uno], %i[uno meta]]
  receipt_orders = [false, true]
  outbound_conflicts = %w[contact generation private ambiguous recipient_alias recipient]
  pdf_bytes = Base64.decode64(<<~BASE64)
    JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC
    9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAg
    MCAxMDAgMTAwXSAvUmVzb3VyY2VzIDw8ID4+IC9Db250ZW50cyA0IDAgUiA+PgplbmRvYmoKNCAwIG9iago8PCAvTGVuZ3RoIDAgPj4Kc3RyZW
    FtCmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDUKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAwIG4gCjAwMDAwMDAwNTggMDAw
    MDAgbiAKMDAwMDAwMDExNSAwMDAwMCBuIAowMDAwMDAwMjE5IDAwMDAwIG4gCnRyYWlsZXIKPDwgL1NpemUgNSAvUm9vdCAxIDAgUiA+PgpzdG
    FydHhyZWYKMjY3CiUlRU9GCg==
  BASE64
  media_formats = [
    { type: 'image', filename: 'synthetic.png', mime_type: 'image/png',
      bytes: Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=') },
    { type: 'audio', filename: 'synthetic.wav', mime_type: 'audio/x-wav',
      bytes: ['524946462600000057415645666d74201000000001000100401f0000803e00000200100064617461020000000000'].pack('H*') },
    { type: 'document', filename: 'synthetic.pdf', mime_type: 'application/pdf', bytes: pdf_bytes }
  ]
  %i[meta uno].each do |principal|
    context "with #{principal} as the configured principal" do
      let!(:inbox_link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                  secondary_inbox: channels.fetch(principal == :meta ? :uno : :meta).inbox,
                                  default_provider: 'whatsapp_cloud', enabled: true, activated_at: 1.day.ago)
      end

      arrival_orders.each do |arrival_order|
        context "when #{arrival_order.join(' then ')} arrives" do
          it 'keeps one bubble/conversation and both operational IDs through repeated deliveries' do # rubocop:disable RSpec/MultipleExpectations
            allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
            original_contact = known_contact.attributes.slice('id', 'name', 'phone_number', 'bsuid', 'additional_attributes', 'created_at')
            payloads = channels.keys.index_with { |provider| webhook(provider, 'phone_incoming') }
            arrival_order.each { |provider| ingest(provider, payloads.fetch(provider).deep_dup) }
            message = public_messages.sole
            conversation = message.conversation
            source_id = message.source_id
            2.times { arrival_order.reverse_each { |provider| ingest(provider, payloads.fetch(provider).deep_dup) } }

            expect(public_messages.reload.pluck(:id)).to eq([message.id])
            expect(account.conversations.pluck(:id)).to eq([conversation.id])
            expect(message.reload.inbox_id).to eq(channels.fetch(principal).inbox.id)
            expect(message.source_id).to eq(source_id)
            expect(message.sender_id).to eq(known_contact.id)
            expect(conversation.contact_id).to eq(known_contact.id)
            expect(known_contact.reload.attributes.slice(*original_contact.keys)).to eq(original_contact)
            expect(account.contacts.pluck(:id)).to eq([known_contact.id])
            expect(meta_alias.reload.source_id).to eq('556587654321')
            expect(uno_alias.reload.source_id).to eq('5565987654321')
            expect(Rails.configuration.dispatcher).to have_received(:dispatch)
              .with('message.created', anything, hash_including(message: message)).once

            channels.each do |provider, channel|
              external_id = payloads.fetch(provider).dig(:entry, 0, :changes, 0, :value, :messages, 0, :id)
              identity = WhatsappMessageIdentity.find_by!(inbox: channel.inbox, external_id: external_id)
              unified_alias = WhatsappUnifiedMessageAlias.find_by!(whatsapp_message_identity: identity)
              expect(unified_alias.whatsapp_unified_message.message_id).to eq(message.id)
            end
          end

          media_formats.each do |media|
            it "reserves #{media[:type]} before a second download, blob, attachment or upload", :aggregate_failures do
              downloads = []
              payloads = channels.keys.index_with { |provider| webhook(provider, "#{media[:type]}_incoming") }
              meta_media = payloads.fetch(:meta).dig(:entry, 0, :changes, 0, :value, :messages, 0, media[:type])
              uno_media = payloads.fetch(:uno).dig(:entry, 0, :changes, 0, :value, :messages, 0, media[:type])
              meta_download_url = "https://media.invalid/#{media[:filename]}"
              stub_request(:get, meta_channel.media_url(meta_media[:id]))
                .to_return(status: 200, body: { url: meta_download_url }.to_json, headers: { 'Content-Type' => 'application/json' })
              uno_download_url = "#{uno_channel.unoapi_api_url}/v15.0/download/#{uno_media[:id]}#{File.extname(media[:filename])}"
              # One common external boundary, never inherited parent/child stubs.
              # Return real in-memory bytes; no filesystem or network download.
              stub_media_downloads(media, [meta_download_url, uno_download_url], downloads)
              # Count actual attachment/blob records, suppress physical storage IO.
              allow(ActiveStorage::Blob.service).to receive(:upload)
              attachment_count = Attachment.count
              blob_count = ActiveStorage::Blob.count
              ingest(:uno, delivered_receipt(payloads.fetch(:uno))) if media[:type] == 'audio'
              2.times { arrival_order.each { |provider| ingest(provider, payloads.fetch(provider).deep_dup) } }

              if media[:type] == 'audio'
                sparse_echo = payloads.fetch(:uno).deep_dup
                change = sparse_echo[:entry].first[:changes].first
                incoming = change[:value].delete(:messages).first
                change[:field] = 'smb_message_echoes'
                change[:value][:message_echoes] = [{ id: incoming[:id], from: uno_channel.phone_number.delete_prefix('+'),
                                                     to: '', timestamp: (incoming[:timestamp].to_i + 10).to_s }]
                ingest(:uno, sparse_echo)
                arrival_order.reverse_each { |provider| ingest(provider, payloads.fetch(provider).deep_dup) }
                identity = WhatsappMessageIdentity.find_by!(inbox: uno_channel.inbox, external_id: incoming[:id])
                expect(identity.observations['direction']).to eq('incoming')
                expect(identity.observations['conflicting_observations']).to be_blank
                expect(WhatsappUnifiedEvent.where(state: 'review')).to be_empty
              end

              expect(public_messages.count).to eq(1)
              expect(account.conversations.count).to eq(1)
              expect(downloads).to eq([arrival_order.first == :meta ? meta_download_url : uno_download_url])
              expect(Attachment.count - attachment_count).to eq(1)
              expect(ActiveStorage::Blob.count - blob_count).to eq(1)
              expect(public_messages.sole.attachments.sole.file.blob)
                .to have_attributes(byte_size: media[:bytes].bytesize, content_type: media[:mime_type])
              expect(ActiveStorage::Blob.service).to have_received(:upload).once
              canonical = public_messages.sole
              file = canonical.attachments.sole.file
              preserved = [canonical.id, canonical.source_id, file.id, file.blob_id]
              ledger = WhatsappUnifiedMessage.find_by!(message: canonical)
              origin = ledger.media_inbox_id
              allow(ActiveStorage::Blob.service).to receive(:exist?).with(file.blob.key).and_return(true)
              Whatsapp::ReconcileUnifiedMediaJob.perform_now(ledger.id)
              expect(ledger.reload).to have_attributes(media_review_status: 'unchanged', media_review_reason: 'single_copy_retained',
                                                       media_inbox_id: origin)
              expect([canonical.id, canonical.source_id, file.reload.id, file.blob_id]).to eq(preserved)
              expect(ActiveStorage::Blob.count - blob_count).to eq(1)
              expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
              expect(Whatsapp::UnifiedReviewService.new(link: inbox_link, actor: nil).list(kind: 'media')[:meta][:total]).to eq(0)
            end
          end

          it 'correlates outgoing echoes and advances status by each transport without regressing read' do
            payloads = channels.keys.index_with { |provider| webhook(provider, 'phone_echo') }
            arrival_order.each { |provider| ingest(provider, payloads.fetch(provider).deep_dup) }
            message = public_messages.sole
            expect(message).to be_outgoing

            [[arrival_order.first, 'delivered'], [arrival_order.last, 'read'], [arrival_order.first, 'sent']].each do |provider, status|
              payload = payloads.fetch(provider).deep_dup
              change = payload[:entry].first[:changes].first
              value = change[:value]
              echo = value.delete(:message_echoes).first
              change[:field] = 'messages'
              value[:statuses] = [{ id: echo[:id], provider_message_id: echo[:provider_message_id],
                                    recipient_id: '5565987654321', status: status, timestamp: '1792152300' }.compact]
              ingest(provider, payload)
              expect(message.reload.status).to eq(status == 'delivered' ? 'delivered' : 'read')
            end
            expect(public_messages.pluck(:id)).to eq([message.id])
            expect(account.conversations.count).to eq(1)
          end
        end
      end

      it 'recovers a committed JSON-store bubble after a worker loses the final ledger update' do
        ingest(:meta, webhook(:meta, 'phone_incoming'))
        message = public_messages.sole
        ledger = WhatsappUnifiedMessage.find_by!(message: message)
        ledger.update!(message: nil, state: 'processing', lease_token: 'expired-worker', lease_expires_at: 1.minute.ago)

        expect { ingest(:uno, webhook(:uno, 'phone_incoming')) }.not_to change(public_messages, :count)
        expect(ledger.reload.message_id).to eq(message.id)
        expect(ledger.state).to eq('ready')
      end

      it 'does not rewrite historical source IDs, conversations or private notes when activated' do
        legacy = create(:conversation, account: account, inbox: uno_channel.inbox, contact: known_contact, contact_inbox: uno_alias)
        old_message = create(:message, account: account, inbox: uno_channel.inbox, conversation: legacy, sender: known_contact,
                                       source_id: 'legacy-public-uuid', created_at: 2.days.ago)
        note = create(:message, account: account, inbox: uno_channel.inbox, conversation: legacy,
                                message_type: :outgoing, private: true, content: 'Nota privada preservada')
        snapshots = [old_message, note].index_with(&:attributes)

        ingest(:meta, webhook(:meta, 'phone_incoming'))
        ingest(:uno, webhook(:uno, 'phone_incoming'))

        snapshots.each { |message, attributes| expect(message.reload.attributes).to eq(attributes) }
        expect(legacy.reload.inbox_id).to eq(uno_channel.inbox.id)
      end

      it 'does not discard an unrelated original merely because the body and timestamp match' do
        ingest(:meta, webhook(:meta, 'phone_incoming'))
        unrelated = webhook(:uno, 'phone_incoming')
        unrelated.dig(:entry, 0, :changes, 0, :value, :messages).first[:provider_message_id] = '3EB0111111111111111111'
        ingest(:uno, unrelated)
        expect(public_messages.count).to eq(2)
      end

      it 'retains a status received before either echo and applies it without creating a status bubble' do
        payload = webhook(:uno, 'phone_echo')
        value = payload[:entry].first[:changes].first[:value]
        echo = value.delete(:message_echoes).first
        payload[:entry].first[:changes].first[:field] = 'messages'
        value[:statuses] = [{ id: echo[:id], provider_message_id: echo[:provider_message_id], recipient_id: '5565987654321',
                              status: 'read', timestamp: '1792152300' }]
        2.times { ingest(:uno, payload.deep_dup) }
        expect(public_messages).to be_empty
        ingest(:meta, webhook(:meta, 'phone_echo'))
        ingest(:uno, webhook(:uno, 'phone_echo'))
        expect(public_messages.count).to eq(1)
        expect(public_messages.sole.status).to eq('read')
        expect(account.conversations.count).to eq(1)
      end

      it 'does not reject a repeated phone identity solely for equivalent Brazilian eighth/ninth-digit observations' do
        payload = webhook(:uno, 'phone_incoming')
        ingest(:uno, payload.deep_dup)
        variant = payload.deep_dup
        value = variant[:entry].first[:changes].first[:value]
        value[:contacts].first[:wa_id] = '556587654321'
        value[:messages].first[:from] = '556587654321'
        ingest(:uno, variant)
        ingest(:meta, webhook(:meta, 'phone_incoming'))

        expect(public_messages.count).to eq(1)
        expect(public_messages.sole.inbox_id).to eq(channels.fetch(principal).inbox.id)
        expect(account.conversations.count).to eq(1)
        expect(known_contact.reload.phone_number).to eq('+5565987654321')
      end

      it 'retains both independent legacy ingestion paths when the link is disabled' do
        inbox_link.update!(enabled: false)
        ingest(:meta, webhook(:meta, 'phone_incoming'))
        ingest(:uno, webhook(:uno, 'phone_incoming'))
        expect(public_messages.count).to eq(2)
        expect(public_messages.pluck(:inbox_id).sort).to eq(channels.values.map { |channel| channel.inbox.id }.sort)
      end

      it 'does not unify delayed historical messages predating activation' do
        channels.each_key do |provider|
          payload = webhook(provider, 'phone_incoming')
          payload.dig(:entry, 0, :changes, 0, :value, :messages).first[:timestamp] = 2.days.ago.to_i.to_s
          ingest(provider, payload)
        end
        expect(public_messages.count).to eq(2)
        expect(public_messages.pluck(:inbox_id).sort).to eq(channels.values.map { |channel| channel.inbox.id }.sort)
      end

      it 'does not reassign an established conflicting BSUID alias', :aggregate_failures do
        other = create(:contact, account: account, name: 'Outra pessoa', phone_number: '+5565987654322')
        conflict = create(:contact_inbox, inbox: meta_channel.inbox, contact: other, source_id: 'BR.1234567890123456')
        ingest(:uno, webhook(:uno, 'bsuid_incoming'))
        ingest(:meta, webhook(:meta, 'bsuid_incoming'))

        expect(conflict.reload.contact_id).to eq(other.id)
        expect(known_contact.reload.name).to eq('Nome humano preservado')
        expect(other.reload.name).to eq('Outra pessoa')
        expect(account.contacts.order(:id).pluck(:id)).to eq([known_contact.id, other.id].sort)
        expect(public_messages.count).to eq(1)
        event = WhatsappUnifiedEvent.where(whatsapp_inbox_link: inbox_link).sole
        expect(event).to have_attributes(state: 'review', reason: 'correlation_conflict', next_attempt_at: nil)
        2.times { Whatsapp::ProcessUnifiedEventJob.perform_now(event.id) }
        expect(public_messages.reload.count).to eq(1)
        expect(conflict.reload.contact_id).to eq(other.id)
      end

      it 'reuses a known BSUID alias without replacing the legacy LID or inventing a phone' do
        bsuid_alias = create(:contact_inbox, inbox: meta_channel.inbox, contact: known_contact, source_id: 'BR.1234567890123456')
        ingest(:meta, webhook(:meta, 'bsuid_incoming'))
        ingest(:uno, webhook(:uno, 'bsuid_incoming'))

        expect(public_messages.count).to eq(1)
        expect(public_messages.sole.conversation.contact_id).to eq(known_contact.id)
        expect(bsuid_alias.reload.contact_id).to eq(known_contact.id)
        expect(known_contact.reload.bsuid).to eq('123456789012345@lid')
        expect(known_contact.phone_number).to eq('+5565987654321')
      end

      directions.each do |direction|
        context "with an unknown BSUID-first #{direction}" do
          let(:event_key) { direction == 'echo' ? :message_echoes : :messages }
          let(:payload) { webhook(:meta, "bsuid_#{direction}") }
          let(:external_id) { payload.dig(:entry, 0, :changes, 0, :value, event_key, 0, :id) }

          it 'durably stages repetitions without a contact, bubble, lookup or download', :aggregate_failures do
            expect(Down).not_to receive(:download)
            expect_any_instance_of(Whatsapp::FacebookApiClient).not_to receive(:fetch_whatsapp_user)
            contacts_before = account.contacts.count
            3.times { ingest(:meta, payload.deep_dup) }

            identity = WhatsappMessageIdentity.find_by!(inbox: meta_channel.inbox, external_id: external_id)
            event = WhatsappUnifiedEvent.find_by!(whatsapp_message_identity: identity, whatsapp_inbox_link: inbox_link)
            expect(event).to have_attributes(state: 'pending', reason: 'identity_pending', attempts: 0,
                                             activation_cutoff: inbox_link.reload.activated_at, next_attempt_at: 15.seconds.from_now)
            expect(event.payload).to eq(payload.dig(:entry, 0, :changes, 0, :value).deep_stringify_keys)
            expect(WhatsappUnifiedEvent.where(whatsapp_message_identity: identity).count).to eq(1)
            expect(Whatsapp::ProcessUnifiedEventJob).to have_been_enqueued.with(event.id).at(15.seconds.from_now)
            expect(public_messages).to be_empty
            expect(account.conversations).to be_empty
            expect(account.contacts.count).to eq(contacts_before)
            expect(meta_channel.inbox.contact_inboxes.where(source_id: 'BR.1234567890123456')).not_to exist
            expect(WhatsappIdentityResolution.where(whatsapp_message_identity: identity)).to be_empty
            expect(WhatsappUnifiedMessage.where(whatsapp_inbox_link: inbox_link)).to be_empty
          end

          it 'replays onto the real old contact and one canonical counterpart without rewriting legacy identities', :aggregate_failures do
            snapshot = known_contact.attributes.slice('id', 'name', 'phone_number', 'bsuid', 'additional_attributes', 'created_at')
            2.times { ingest(:meta, payload.deep_dup) }
            identity = WhatsappMessageIdentity.find_by!(inbox: meta_channel.inbox, external_id: external_id)
            event = WhatsappUnifiedEvent.find_by!(whatsapp_message_identity: identity)
            counterpart = webhook(:uno, "bsuid_#{direction}")
            2.times { ingest(:uno, counterpart.deep_dup) }
            message = public_messages.sole
            original_source = message.source_id

            travel 16.seconds
            3.times { Whatsapp::ProcessUnifiedEventJob.perform_now(event.id) }
            ingest(:meta, payload.deep_dup)
            ingest(:uno, counterpart.deep_dup)

            expect(public_messages.reload.pluck(:id)).to eq([message.id])
            expect(account.conversations.pluck(:id)).to eq([message.conversation_id])
            expect(message.reload).to have_attributes(inbox_id: channels.fetch(principal).inbox.id, source_id: original_source)
            expect(message.conversation.contact_id).to eq(known_contact.id)
            expect(known_contact.reload.attributes.slice(*snapshot.keys)).to eq(snapshot)
            expect(account.contacts.pluck(:id)).to eq([known_contact.id])
            expect(meta_alias.reload.source_id).to eq('556587654321')
            expect(uno_alias.reload.source_id).to eq('5565987654321')
            expect(meta_channel.inbox.contact_inboxes.find_by!(source_id: 'BR.1234567890123456').contact_id).to eq(known_contact.id)
            expect(described_class.message_for(identity).id).to eq(message.id)
            expect(event.reload).to have_attributes(state: 'completed', payload: {}, next_attempt_at: nil)
          end

          it 'stages media before performing even its first download' do
            media_payload = payload.deep_dup
            body = media_payload.dig(:entry, 0, :changes, 0, :value, event_key, 0)
            body.delete(:text)
            body[:type] = 'image'
            body[:image] = { id: 'synthetic-bsuid-image', mime_type: 'image/png' }
            expect(Down).not_to receive(:download)
            blob_count = ActiveStorage::Blob.count
            attachment_count = Attachment.count

            2.times { ingest(:meta, media_payload.deep_dup) }

            expect(public_messages).to be_empty
            expect(account.contacts.pluck(:id)).to eq([known_contact.id])
            expect(Attachment.count).to eq(attachment_count)
            expect(ActiveStorage::Blob.count).to eq(blob_count)
            expect(WhatsappUnifiedEvent.where(whatsapp_inbox_link: inbox_link).sole)
              .to have_attributes(state: 'pending', reason: 'identity_pending')
          end
        end
      end

      # Full lifecycle assertions intentionally keep public IDs, files and
      # dispatch side effects together in each matrix case.
      # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
      context 'with a late partner echo after a Meta API send' do
        around do |example|
          Dir.mktmpdir('unified-late-echo-') do |directory|
            example.metadata[:late_echo_storage] = directory
            example.run
          end
        ensure
          example.metadata.delete(:late_echo_storage)
        end

        before do
          service = ActiveStorage::Service::DiskService.new(root: RSpec.current_example.metadata.fetch(:late_echo_storage))
          service.name = ActiveStorage::Blob.service.name
          allow(ActiveStorage::Blob).to receive(:service).and_return(service)
          allow(ActiveStorage::Blob.services).to receive(:fetch).and_return(service)
        end

        outbound_conflicts.product([true, false]).each do |conflict, recipient_present|
          next if recipient_present && %w[recipient_alias recipient].include?(conflict)

          it "holds a #{conflict} conflict, recipient_present=#{recipient_present} instead of adopting or creating a second bubble" do
            ingest(:meta, webhook(:meta, 'phone_incoming'))
            ingest(:uno, webhook(:uno, 'phone_incoming'))
            conversation = public_messages.sole.conversation
            peer = '556587654321'
            original_id = 'CE550277C18EADC4F0ED'
            envelope = "\x1c\x18#{peer.bytesize.chr}#{peer}\x15\x02\x00\x11\x18#{original_id.bytesize.chr}#{original_id}\x00"
            meta_id = "wamid.#{Base64.strict_encode64(envelope)}"
            agent = create(:user, account: account)
            outgoing = Messages::MessageBuilder.new(agent, conversation,
                                                    ActionController::Parameters.new(content: 'opa', whatsapp_transport: 'whatsapp_cloud')).perform
            expect_any_instance_of(Channel::Whatsapp).to receive(:send_message).once.and_return(meta_id)
            Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
            case conflict
            when 'contact'
              conversation.update!(contact: create(:contact, account: account, phone_number: '+5511987654321'))
            when 'generation'
              attributes = outgoing.reload.content_attributes.deep_dup
              attributes['whatsapp_transport']['activation_cutoff'] = 1.day.ago.iso8601(6)
              outgoing.update!(content_attributes: attributes)
            when 'private'
              outgoing.update!(private: true)
            when 'ambiguous'
              identity = WhatsappMessageIdentity.find_by!(inbox: meta_channel.inbox, external_id: meta_id).dup
              identity.external_id = 'another-provider-public-id'
              identity.save!
            end
            ids = account.messages.order(:id).pluck(:id, :source_id)
            payload = webhook(:uno, 'phone_echo')
            echo = payload.dig(:entry, 0, :changes, 0, :value, :message_echoes, 0)
            echo[:id] = '20000000-0000-4000-8000-000000000002'
            echo[:provider_message_id] = original_id
            echo.delete(:to) unless recipient_present
            echo[:to_user_id] = 'BR.9999999999999999' if conflict == 'recipient_alias'
            echo[:to] = '5511987654321' if conflict == 'recipient'

            2.times { ingest(:uno, payload.deep_dup) }

            expect(account.messages.order(:id).pluck(:id, :source_id)).to eq(ids)
            expect(WhatsappUnifiedMessage.find_by(original_id: original_id)&.message_id).to be_nil
            review = recipient_present || %w[generation recipient_alias recipient].include?(conflict)
            expect(WhatsappUnifiedEvent.where(whatsapp_inbox_link: inbox_link).sole)
              .to have_attributes(state: review ? 'review' : 'pending', reason: review ? 'correlation_conflict' : 'identity_pending')
          end
        end

        [{ type: 'text', quoted: false }, { type: 'text', quoted: true }, *media_formats].each do |variant|
          receipt_orders.product([true, false]).each do |receipt_first, recipient_present|
            it "reuses #{variant[:type]} quote=#{variant[:quoted] != false}, receipt=#{receipt_first}, recipient=#{recipient_present}" do
              unless recipient_present
                meta_channel.update!(phone_number: '+556696222471')
                uno_channel.update!(phone_number: '+5566996222471')
              end
              ingest(:meta, webhook(:meta, 'phone_incoming'))
              ingest(:uno, webhook(:uno, 'phone_incoming'))
              quoted = public_messages.sole
              unless recipient_present
                known_contact.update!(phone_number: '+5566996269251')
                meta_alias.update!(source_id: '556696269251')
                uno_alias.update!(source_id: '5566996269251')
              end
              original_id = recipient_present ? 'CE550277C18EADC4F0ED' : 'CEAE20230B67E95629AF'
              peer = recipient_present ? '556587654321' : '556696269251'
              envelope = "\x1c\x18#{peer.bytesize.chr}#{peer}\x15\x02\x00\x11\x18#{original_id.bytesize.chr}#{original_id}\x00"
              meta_id = "wamid.#{Base64.strict_encode64(envelope)}"
              params = ActionController::Parameters.new(content: 'opa', message_type: 'outgoing', whatsapp_transport: 'whatsapp_cloud')
              params[:content_attributes] = { in_reply_to: quoted.id } unless variant[:quoted] == false
              if variant[:bytes]
                blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(variant[:bytes]), filename: variant[:filename],
                                                              content_type: variant[:mime_type])
                params[:attachments] = [blob.signed_id]
                params[:is_voice_message] = variant[:type] == 'audio'
              end
              agent = create(:user, account: account)
              outgoing = Messages::MessageBuilder.new(agent, quoted.conversation, params).perform
              expect_any_instance_of(Channel::Whatsapp).to receive(:send_message).once.and_return(meta_id)
              Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
              preserved_ids = public_messages.order(:id).pluck(:id, :source_id)
              attachment_ids = outgoing.attachments.pluck(:id)
              file_ids = outgoing.attachments.map { |item| [item.file.id, item.file.blob_id] }
              counts = [Message.count, Attachment.count, ActiveStorage::Blob.count, account.conversations.count, account.contacts.count]
              allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
              expect(Down).not_to receive(:download)
              expect(ActiveStorage::Blob.service).not_to receive(:upload)

              payload = webhook(:uno, 'phone_echo')
              echo = payload[:entry].first[:changes].first[:value][:message_echoes].first
              echo.merge!(id: '20000000-0000-4000-8000-000000000002', provider_message_id: original_id,
                          type: variant[:type], timestamp: (Time.current.to_i + 2).to_s)
              unless recipient_present
                echo[:id] = 'c1bf97d0-ca1c-11f1-8b89-01afaf97c044'
                echo.delete(:to)
                payload[:entry].first[:changes].first[:value].delete(:contacts)
              end
              unless variant[:quoted] == false
                echo[:context] = { id: webhook(:uno, 'phone_incoming').dig(:entry, 0, :changes, 0, :value, :messages, 0, :id) }
              end
              if variant[:bytes]
                echo.delete(:text)
                echo[variant[:type]] = { id: 'must-not-download', mime_type: variant[:mime_type], caption: '*Rodrigo*: opa' }
              else
                echo[:text][:body] = '*Rodrigo*: opa'
              end
              status_payload = webhook(:meta, 'phone_echo')
              value = status_payload[:entry].first[:changes].first[:value]
              value.delete(:message_echoes)
              value.delete(:contacts) unless recipient_present
              value[:statuses] = [{ id: meta_id, recipient_id: peer, status: 'read', timestamp: Time.current.to_i.to_s }]
              ingest(:meta, status_payload.deep_dup) if receipt_first
              3.times { ingest(:uno, payload.deep_dup) }
              ingest(:meta, status_payload.deep_dup)

              expect(public_messages.order(:id).pluck(:id, :source_id)).to eq(preserved_ids)
              expect([Message.count, Attachment.count, ActiveStorage::Blob.count, account.conversations.count, account.contacts.count]).to eq(counts)
              expect(outgoing.reload).to have_attributes(source_id: meta_id, sender_id: agent.id, content: 'opa', status: 'read')
              unless variant[:quoted] == false
                expect(outgoing.content_attributes['in_reply_to']).to eq(quoted.id)
                expect(Whatsapp::UnifiedTransportService.new(message: outgoing).reference_for(quoted))
                  .to eq(webhook(:meta, 'phone_incoming').dig(:entry, 0, :changes, 0, :value, :messages, 0, :id))
                expect(meta_channel.provider_service.send(:whatsapp_reply_context, outgoing))
                  .to eq(message_id: webhook(:meta, 'phone_incoming').dig(:entry, 0, :changes, 0, :value, :messages, 0, :id))
              end
              record = WhatsappUnifiedMessage.find_by!(whatsapp_inbox_link: inbox_link, original_id: original_id, direction: 'outgoing')
              expect(record).to have_attributes(message_id: outgoing.id, state: 'ready')
              expect(record.identities.order(:provider).pluck(:external_id)).to eq([echo[:id], meta_id])
              if variant[:bytes]
                Whatsapp::ReconcileUnifiedMediaJob.perform_now(record.id)
                expect(record.reload).to have_attributes(media_review_status: 'unchanged', media_review_reason: 'single_copy_retained',
                                                         media_inbox_id: meta_channel.inbox.id)
              end
              expect(outgoing.attachments.pluck(:id)).to eq(attachment_ids)
              expect(outgoing.attachments.map { |item| [item.file.id, item.file.blob_id] }).to eq(file_ids)
              expect(outgoing.attachments.sole.file.download).to eq(variant[:bytes]) if variant[:bytes]
              expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
              expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::MESSAGE_CREATED, anything, anything)

              # Incomplete peer evidence may retain the already proven single
              # file, but must never authorize reconciliation of a second copy.
              if variant[:bytes] && !recipient_present
                secondary = inbox_link.secondary_inbox
                duplicate_conversation = create(:conversation, account: account, inbox: secondary, contact: known_contact)
                duplicate = create(:message, account: account, inbox: secondary, conversation: duplicate_conversation,
                                             message_type: :outgoing, source_id: 'synthetic-conflicting-copy')
                record.identities.find_by!(inbox: secondary).message_links.create!(message: duplicate)
                result = Whatsapp::UnifiedMediaReconciliationService.new(record: record).perform
                expect(result).to have_attributes(status: :review, reason: :untrusted_mapping)
                expect(outgoing.attachments.map { |item| [item.file.id, item.file.blob_id] }).to eq(file_ids)
                expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
              end
            end
          end
        end
      end

      # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
      %i[meta uno].each do |sending_provider|
        it "adopts only the exact #{sending_provider} API response after an early echo, never a similar pending bubble", :aggregate_failures do
          conversation = create(:conversation, account: account, inbox: inbox_link.primary_inbox, contact: known_contact,
                                               contact_inbox: principal == :meta ? meta_alias : uno_alias)
          # Open the real Meta reply window; this message is not an outbound candidate.
          create(:message, account: account, inbox: meta_channel.inbox, conversation: conversation,
                           sender: known_contact, message_type: :incoming)
          agent = create(:user, account: account)
          params = ActionController::Parameters.new(content: 'Mensagem sintética de coexistência', message_type: 'outgoing',
                                                    whatsapp_transport: channels.fetch(sending_provider).provider)
          decoy = Messages::MessageBuilder.new(agent, conversation, params.deep_dup).perform
          optimistic = Messages::MessageBuilder.new(agent, conversation, params.deep_dup).perform
          payload = webhook(sending_provider, 'phone_echo')
          external_id = payload.dig(:entry, 0, :changes, 0, :value, :message_echoes, 0, :id)
          before_ids = public_messages.pluck(:id).sort
          expect_any_instance_of(Channel::Whatsapp).to receive(:send_message).once do |_channel, _recipient, sent|
            expect(sent.id).to eq(optimistic.id)
            2.times { ingest(sending_provider, payload.deep_dup) }
            expect(public_messages.reload.pluck(:id).sort).to eq(before_ids)
            expect(WhatsappUnifiedEvent.where(whatsapp_inbox_link: inbox_link).sole)
              .to have_attributes(state: 'pending', reason: 'outbound_response_pending')
            external_id
          end

          Whatsapp::SendOnWhatsappService.new(message: optimistic).perform
          identity = WhatsappMessageIdentity.find_by!(inbox: channels.fetch(sending_provider).inbox, external_id: external_id)
          expect(WhatsappUnifiedMessageAlias.find_by!(whatsapp_message_identity: identity).message_id).to eq(optimistic.id)
          event = WhatsappUnifiedEvent.find_by!(whatsapp_message_identity: identity)
          travel 16.seconds
          3.times { Whatsapp::ProcessUnifiedEventJob.perform_now(event.id) }
          ingest(sending_provider, payload.deep_dup)

          expect(public_messages.reload.pluck(:id).sort).to eq(before_ids)
          expect(optimistic.reload.source_id).to eq(external_id)
          expect(decoy.reload.source_id).to be_nil
          expect(described_class.message_for(identity).id).to eq(optimistic.id)
          expect(event.reload).to have_attributes(state: 'completed', payload: {}, next_attempt_at: nil)
        end
      end

      attempting_states.each do |state|
        it "does not let another contact's #{state} delivery block either provider echo" do
          other = create(:contact, account: account, phone_number: '+5511987654321')
          other_conversation = create(:conversation, account: account, inbox: inbox_link.primary_inbox, contact: other)
          agent = create(:user, account: account)
          pending_params = ActionController::Parameters.new(content: 'Pending other contact', whatsapp_transport: 'unoapi')
          blocker = Messages::MessageBuilder.new(agent, other_conversation, pending_params).perform
          attributes = blocker.content_attributes.deep_dup
          attributes['whatsapp_transport'].merge!('delivery_state' => state, 'delivery_attempt_id' => SecureRandom.uuid)
          blocker.update!(status: :progress, content_attributes: attributes)
          snapshot = blocker.attributes

          2.times { channels.each_key { |provider| ingest(provider, webhook(provider, 'phone_echo')) } }

          canonical = public_messages.where.not(id: blocker.id).sole
          expect(canonical.conversation.contact_id).to eq(known_contact.id)
          expect(WhatsappUnifiedMessage.find_by!(message: canonical).identities.count).to eq(2)
          expect(WhatsappUnifiedEvent.where(whatsapp_inbox_link: inbox_link)).to be_empty
          expect(blocker.reload.attributes).to eq(snapshot)
          expect(public_messages.count).to eq(2)
        end
      end

      it 'adopts an exact confirmed Uno response despite another uncertain delivery to the same contact' do
        ingest(:meta, webhook(:meta, 'phone_incoming'))
        ingest(:uno, webhook(:uno, 'phone_incoming'))
        conversation = public_messages.sole.conversation
        agent = create(:user, account: account)
        params = ActionController::Parameters.new(content: 'Confirmed response', whatsapp_transport: 'unoapi')
        confirmed = Messages::MessageBuilder.new(agent, conversation, params).perform
        payloads = channels.keys.index_with { |provider| webhook(provider, 'phone_echo') }
        original = '3EB05EEB24EFB6B701108C'
        peer = '556587654321'
        envelope = "\x1c\x18#{peer.bytesize.chr}#{peer}\x15\x02\x00\x11\x18#{original.bytesize.chr}#{original}\x00"
        external_id = 'f0000000-0000-4000-8000-000000000001'
        payloads[:uno].dig(:entry, 0, :changes, 0, :value, :message_echoes).first.merge!(id: external_id, provider_message_id: original)
        payloads[:meta].dig(:entry, 0, :changes, 0, :value, :message_echoes).first[:id] = "wamid.#{Base64.strict_encode64(envelope)}"
        expect_any_instance_of(Channel::Whatsapp).to receive(:send_message).once.and_return(external_id)
        Whatsapp::SendOnWhatsappService.new(message: confirmed).perform
        blocker = Messages::MessageBuilder.new(agent, conversation, params.deep_dup).perform
        attributes = blocker.content_attributes.deep_dup
        attributes['whatsapp_transport'].merge!('delivery_state' => 'uncertain', 'delivery_attempt_id' => SecureRandom.uuid)
        blocker.update!(status: :progress, content_attributes: attributes)
        snapshot = blocker.attributes
        ids = public_messages.order(:id).pluck(:id, :source_id)

        value = payloads[:meta].dig(:entry, 0, :changes, 0, :value)
        Whatsapp::MessageIdentityObservationService.new(inbox: meta_channel.inbox, value: value, outgoing_echo: true).perform
        identity = WhatsappMessageIdentity.find_by!(inbox: meta_channel.inbox, provider_message_id: original)
        staged = Whatsapp::UnifiedEventService.defer(link: inbox_link, identity: identity, value: value, reason: 'outbound_response_pending')
        providers = %i[uno meta]
        2.times { providers.each { |provider| ingest(provider, payloads.fetch(provider).deep_dup) } }
        travel 16.seconds
        Whatsapp::ProcessUnifiedEventJob.perform_now(staged.id)

        expect(public_messages.order(:id).pluck(:id, :source_id)).to eq(ids)
        expect(WhatsappUnifiedMessage.find_by!(message: confirmed).identities.count).to eq(2)
        expect(staged.reload).to have_attributes(state: 'completed', reason: 'correlated', payload: {}, next_attempt_at: nil)
        expect(blocker.reload.attributes).to eq(snapshot)
      end

      it 'promotes an already staged BSUID event to review when a conflicting contact alias appears before replay' do
        payload = webhook(:meta, 'bsuid_incoming')
        ingest(:meta, payload.deep_dup)
        event = WhatsappUnifiedEvent.where(whatsapp_inbox_link: inbox_link).sole
        ingest(:uno, webhook(:uno, 'bsuid_incoming'))
        canonical = public_messages.sole
        other = create(:contact, account: account, name: 'Outra pessoa', phone_number: '+5565987654322')
        conflict = create(:contact_inbox, inbox: meta_channel.inbox, contact: other, source_id: 'BR.1234567890123456')
        travel 16.seconds

        Whatsapp::ProcessUnifiedEventJob.perform_now(event.id)

        expect(event.reload).to have_attributes(state: 'review', reason: 'correlation_conflict', next_attempt_at: nil)
        expect(event.payload).to be_present
        expect(public_messages.reload.pluck(:id)).to eq([canonical.id])
        expect(conflict.reload.contact_id).to eq(other.id)
        expect(known_contact.reload).to have_attributes(phone_number: '+5565987654321', bsuid: '123456789012345@lid')
      end

      it 'blocks an outgoing message prepared before unlink/reactivate instead of sending it under the new activation' do
        conversation = create(:conversation, account: account, inbox: inbox_link.primary_inbox, contact: known_contact,
                                             contact_inbox: principal == :meta ? meta_alias : uno_alias)
        agent = create(:user, account: account)
        params = ActionController::Parameters.new(content: 'Envio pendente', message_type: 'outgoing', whatsapp_transport: 'unoapi')
        optimistic = Messages::MessageBuilder.new(agent, conversation, params).perform
        original_metadata = optimistic.reload.content_attributes.fetch('whatsapp_transport').deep_dup
        expect(original_metadata.fetch('activation_cutoff')).to eq(inbox_link.reload.activated_at.iso8601(6))
        inbox_link.update!(enabled: false)
        travel 1.minute
        inbox_link.update!(enabled: true)
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_message)

        expect { Whatsapp::SendOnWhatsappService.new(message: optimistic).perform }
          .to raise_error(ArgumentError, /link changed/)
        expect(optimistic.reload.source_id).to be_nil
        expect(optimistic.content_attributes.fetch('whatsapp_transport')).to eq(original_metadata)
      end

      it 'does not let the same external/original ID join another account' do
        other_account = create(:account)
        other_channel = create(:channel_whatsapp, account: other_account, provider: 'unoapi',
                                                  phone_number: "+556598#{business_suffix}",
                                                  sync_templates: false, validate_provider_config: false)
        payload = webhook(:uno, 'phone_incoming')
        payload[:entry].first[:changes].first[:value][:metadata][:display_phone_number] = other_channel.phone_number.delete_prefix('+')
        Whatsapp::IncomingMessageUnoapiService.new(inbox: other_channel.inbox, params: payload).perform
        other_message = other_account.messages.where(message_type: :incoming).sole
        snapshot = other_message.attributes

        ingest(:meta, webhook(:meta, 'phone_incoming'))
        ingest(:uno, webhook(:uno, 'phone_incoming'))

        expect(public_messages.count).to eq(1)
        expect(other_message.reload.attributes).to eq(snapshot)
        expect(other_message.conversation.account_id).to eq(other_account.id)
        expect(public_messages.sole.id).not_to eq(other_message.id)
      end

      it 'leaves Web inbox messages and their private notes outside WhatsApp routing' do
        web = create(:conversation, account: account, contact: known_contact)
        web_message = create(:message, account: account, inbox: web.inbox, conversation: web, sender: known_contact)
        note = create(:message, account: account, inbox: web.inbox, conversation: web, message_type: :outgoing, private: true)
        snapshots = [web_message, note].index_with(&:attributes)
        ingest(:meta, webhook(:meta, 'phone_incoming'))
        ingest(:uno, webhook(:uno, 'phone_incoming'))

        snapshots.each { |message, attributes| expect(message.reload.attributes).to eq(attributes) }
        expect(web.reload.inbox.channel_type).to eq('Channel::WebWidget')
      end
    end
  end
end
# rubocop:enable RSpec/AnyInstance
