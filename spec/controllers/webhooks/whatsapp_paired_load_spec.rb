require 'uri'

if ENV['WHATSAPP_REPLAY_CASES'].to_s != ''
  database = ENV['DATABASE_URL'].to_s.empty? ? ENV.fetch('POSTGRES_DATABASE', nil) : URI(ENV.fetch('DATABASE_URL')).path.delete_prefix('/')
  abort('Private paired replay requires its isolated test database') unless
    ENV['RAILS_ENV'] == 'test' && database == 'viperchat_meta_paired_load_test'
end

require 'rails_helper'
require 'base64'
require 'tempfile'

# Synthetic batch stress, NOT ten fresh production captures. Envelopes derive
# from spec/fixtures/whatsapp_coexistence; every participant/public/original ID
# in the default mode is newly generated synthetic data. Correlation is exact-ID-only:
# synthetic contacts deliberately send identical content at the same timestamp.
# Keep the entire batch and its per-contact assertions in one transaction;
# hook expectations are explicit guards against unexpected external side effects.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/ExpectInHook, Performance/CollectionLiteralInLoop
RSpec.describe 'Paired WhatsApp ten-conversation load', type: :request do
  # Optional private input is never a fixture, never logged and never checked in.
  # A replay still has SIMULATED Meta counterparts and SIMULATED media bytes.
  # WHATSAPP_REPLAY_CASES=/private/cases.json bundle exec rspec <this spec>
  sources = ['synthetic envelopes and media bytes']
  sources << 'real Uno envelopes; simulated Meta partner and media bytes' if ENV['WHATSAPP_REPLAY_CASES'].present?
  sources.each do |source|
    context source do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:replay_mode) { source.start_with?('real Uno') }
      let(:replay_rows) { replay_mode ? JSON.parse(File.read(ENV.fetch('WHATSAPP_REPLAY_CASES'))) : [] }
      let(:expected_messages) { replay_mode ? 10 : 20 }
      let(:expected_media) { replay_mode ? replay_rows.count { |row| row.fetch('message').fetch('type') != 'text' } : 10 }
      let(:download_files) { [] }
      let(:ogg_bytes) do
        Base64.strict_decode64(
          'T2dnUwACAAAAAAAAAAAZqwzpAAAAAC9iby0BE09wdXNIZWFkAQE4AUAfAAAAAABPZ2dTAAAAAAAAAAAAABmrDOkBAAAALKOBDQE+' \
          'T3B1c1RhZ3MNAAAATGF2ZjYwLjE2LjEwMAEAAAAdAAAAZW5jb2Rlcj1MYXZjNjAuMzEuMTAyIGxpYm9wdXNPZ2dTAAT4BAAAAAAAABmrDOkCAAAAmSK7fwIDA5j//pj//g=='
        )
      end
      let(:account) { create(:account) }
      let(:secret) { 'synthetic-paired-load-hmac-secret' }
      let(:meta_channel) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                                  provider_config: { 'api_key' => 'synthetic', 'phone_number_id' => 'synthetic-meta', 'app_secret' => secret },
                                  sync_templates: false, validate_provider_config: false)
      end
      let(:uno_channel) do
        create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                                  provider_config: { 'api_key' => 'synthetic', 'url' => 'https://uno.invalid',
                                                     'phone_number_id' => 'synthetic-uno' },
                                  sync_templates: false, validate_provider_config: false)
      end
      let(:channels) { { meta: meta_channel, uno: uno_channel } }
      let(:png_bytes) do
        Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
      end
      let(:cases) do
        if replay_mode
          normalized = replay_rows.map { |row| Whatsapp::InboxLinkPhoneService.normalize(row.fetch('peer')) }
          unless replay_rows.size == 10 && normalized.compact.uniq.size == 10
            raise ArgumentError, 'Private replay requires ten distinct normalized contacts, not ten raw peer forms'
          end
          unless replay_rows.map { |row| row.fetch('production_conversation_id') }.uniq.size == 10 &&
                 replay_rows.map { |row| row.fetch('known_contact').fetch('id') }.uniq.size == 10 &&
                 replay_rows.map { |row| row.fetch('known_contact').fetch('account_id') }.uniq.one?
            raise ArgumentError, 'Private replay requires ten verified source conversations/contacts from one account'
          end
          unless replay_rows.all? do |row|
            message = row.fetch('message')
            message.fetch('from') == row.fetch('peer') && %w[audio text].include?(message.fetch('type')) &&
            message.fetch('provider_message_id').match?(/\A[A-F0-9]{16,64}\z/)
          end
            raise ArgumentError, 'Private replay requires explicit peer and original-ID evidence; no semantic inference is allowed'
          end
        end
        Array.new(10) do |index|
          captured = replay_mode ? replay_rows.fetch(index) : nil
          peer = captured ? captured.fetch('peer') : "55659876543#{index}0"
          phone = captured ? captured.fetch('known_contact').fetch('phone_number') : "+#{Whatsapp::InboxLinkPhoneService.normalize(peer)}"
          bsuid = captured&.fetch('known_contact')&.fetch('bsuid')
          contact = create(:contact, account: account, phone_number: phone, bsuid: bsuid, name: "Synthetic preserved #{index}",
                                     additional_attributes: { 'manual_reference' => "synthetic-#{index}" })
          # Source aliases are verified contact associations. Their assignment
          # to BOTH test partners is simulated, not captured Meta identity data.
          aliases = captured ? captured.fetch('known_contact').fetch('aliases').map(&:last) : []
          aliases = [peer, phone&.delete_prefix('+'), bsuid, *aliases].compact_blank.uniq
          channels.each_value do |channel|
            aliases.each { |source_id| create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: source_id) }
          end
          { index: index, peer: peer, contact: contact, captured: captured }
        end
      end
      let(:downloads) { [] }
      let(:uploads) { {} }
      let(:public_messages) { account.messages.where(message_type: %i[incoming outgoing], private: false) }

      around do |example|
        network = WebMock::Config.instance.allow_net_connect
        localhost = WebMock::Config.instance.allow_localhost
        adapter = ActiveJob::Base.queue_adapter
        loggers = [Rails.logger, ActiveRecord::Base.logger, ActiveJob::Base.logger, ActionController::Base.logger].compact.uniq
        levels = loggers.index_with(&:level)
        loggers.each { |logger| logger.level = Logger::FATAL } if replay_mode
        ActiveJob::Base.queue_adapter = :test
        WebMock.disable_net_connect!(allow_localhost: false)
        travel_to(Time.at(1_792_151_940).utc) { example.run }
      ensure
        clear_enqueued_jobs
        clear_performed_jobs
        download_files.each(&:close!)
        levels&.each { |logger, level| logger.level = level }
        ActiveJob::Base.queue_adapter = adapter
        WebMock::Config.instance.allow_net_connect = network
        WebMock::Config.instance.allow_localhost = localhost
      end

      before do
        # Only external IO is mocked. Domain services, controller, HMAC, envelope
        # splitting, Webhooks job, locks and all database records remain real.
        allow(ActiveStorage::Blob.service).to receive(:upload) do |key, io, **|
          expect(uploads).not_to have_key(key)
          uploads[key] = io.read
          io.rewind
        end
        allow(ActiveStorage::Blob.service).to receive(:download) { |key| uploads.fetch(key) }
        expect(ActiveStorage::Blob.service).not_to receive(:delete)
        cases.each do |row|
          kinds(row).each do |kind|
            next if kind == :text

            channels.each do |provider, channel|
              media = event_message(provider, row, kind).fetch(kind.to_s)
              download_url = media_download_url(provider, row, kind)
              stub_request(:get, channel.media_url(media.fetch('id')))
                .to_return(status: 200, body: { url: download_url }.to_json, headers: { 'Content-Type' => 'application/json' })
              allow(Down).to receive(:download).with(download_url, headers: anything) do |url|
                downloads << url
                bytes = kind == :audio ? ogg_bytes : png_bytes
                filename = kind == :audio ? 'synthetic.oga' : 'synthetic.png'
                mime = kind == :audio ? 'audio/ogg' : 'image/png'
                Tempfile.new(['paired-load-', File.extname(filename)]).tap do |io|
                  download_files << io
                  io.binmode
                  io.write(bytes)
                  io.rewind
                  io.define_singleton_method(:original_filename) { filename }
                  io.define_singleton_method(:content_type) { mime }
                end
              end
            end
          end
        end
      end

      # Wire helpers remove repeated fixture rewriting/signing; scenario assertions
      # below still enumerate every contact, external ID, ledger and stored blob.
      def original_id(row, kind)
        return row.fetch(:captured).fetch('message').fetch('provider_message_id') if replay_mode

        format('3EB0%<index>016X%<kind>02X', index: row.fetch(:index), kind: kind == :text ? 1 : 2)
      end

      def external_id(provider, row, kind)
        return row.fetch(:captured).fetch('message').fetch('id') if replay_mode && provider == :uno
        return format('20000000-0000-4000-8000-%<id>012d', id: (row.fetch(:index) * 2) + (kind == :text ? 1 : 2)) if provider == :uno

        peer = row.fetch(:peer)
        original = original_id(row, kind)
        envelope = "\x1c\x18".b + peer.bytesize.chr + peer + "\x15\x02\x00\x12\x18".b + original.bytesize.chr + original + "\x00".b
        "wamid.#{Base64.strict_encode64(envelope)}"
      end

      def kinds(row)
        replay_mode ? [row.fetch(:captured).fetch('message').fetch('type').to_sym] : %i[text image]
      end

      def event_message(provider, row, kind) # rubocop:disable Metrics/AbcSize
        return replay_message(provider, row, kind) if replay_mode

        name = kind == :text ? 'phone' : 'image'
        payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence', "#{provider}_#{name}_incoming.json").read)
        message = payload.fetch('entry').first.fetch('changes').first.fetch('value').fetch('messages').first
        message.merge!('id' => external_id(provider, row, kind), 'from' => row.fetch(:peer), 'timestamp' => Time.current.to_i.to_s)
        message['provider_message_id'] = original_id(row, kind) if provider == :uno
        if kind == :image
          message['image']['id'] = provider == :uno ? "synthetic-session/media-#{row[:index]}" : "synthetic-meta-media-#{row[:index]}"
        end
        message
      end

      def replay_message(provider, row, kind)
        message = row.fetch(:captured).fetch('message').deep_dup
        return message if provider == :uno

        message['id'] = external_id(provider, row, kind)
        message.delete('provider_message_id')
        message.delete('from_user_id')
        message[kind.to_s]['id'] = "synthetic-meta-media-#{row[:index]}" unless kind == :text
        message
      end

      def media_download_url(provider, row, kind)
        media = event_message(provider, row, kind).fetch(kind.to_s)
        extension = File.extname(media.fetch('filename'))
        return "https://media.invalid/synthetic-meta-media-#{row[:index]}#{extension}" if provider == :meta

        "#{uno_channel.unoapi_api_url}/v15.0/download/#{media.fetch('id')}#{extension}"
      end

      def batch(provider, rows = cases) # rubocop:disable Metrics/AbcSize
        channel = channels.fetch(provider)
        changes = rows.flat_map do |row|
          kinds(row).map do |kind|
            value = if replay_mode && provider == :uno
                      row.fetch(:captured).fetch('payload').fetch('entry').first.fetch('changes').first.fetch('value').deep_dup
                    else
                      { 'messaging_product' => 'whatsapp',
                        'contacts' => [{ 'wa_id' => row.fetch(:peer), 'profile' => { 'name' => row.fetch(:contact).name } }] }
                    end
            value['metadata'] = { 'display_phone_number' => channel.phone_number.delete_prefix('+'),
                                  'phone_number_id' => channel.provider_config.fetch('phone_number_id') }
            value['messages'] = [event_message(provider, row, kind)]
            { field: 'messages', value: value }
          end
        end
        { object: 'whatsapp_business_account', entry: [{ id: 'synthetic-business', changes: changes }] }.to_json
      end

      def deliver(provider, rows = cases, url_provider: provider)
        body = batch(provider, rows)
        # The production Uno endpoint intentionally bypasses Meta HMAC validation;
        # Meta requests here exercise the actual HMAC verifier, not a stub.
        headers = { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}" }
        perform_enqueued_jobs(only: [Webhooks::WhatsappEventsJob]) do
          post "/webhooks/whatsapp/#{channels.fetch(url_provider).phone_number}", params: body, headers: headers
        end
        expect(response).to have_http_status(:ok)
      end

      %i[meta uno].each do |principal|
        %w[whatsapp_cloud unoapi].each do |default_provider|
          [%i[meta uno], %i[uno meta]].each do |order|
            it "preserves ten mappings with #{principal} principal, #{default_provider} default, #{order.join(' then ')} and retries" do
              link = WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                               secondary_inbox: channels.fetch(principal == :meta ? :uno : :meta).inbox,
                                               default_provider: default_provider, enabled: true, activated_at: 30.days.ago)
              contacts_before = cases.map { |row| row[:contact].attributes.slice('id', 'name', 'phone_number', 'bsuid', 'additional_attributes') }
              contact_ids = cases.map { |row| row[:contact].id }
              aliases_before = ContactInbox.where(contact_id: contact_ids).order(:id).pluck(:id, :contact_id, :inbox_id, :source_id)
              blobs_before = ActiveStorage::Blob.count
              attachments_before = Attachment.count
              stored_before = ActiveStorage::Attachment.count

              # Metadata must select the partner even when URL points to the sibling.
              deliver(order.first, cases, url_provider: order.last)
              first_snapshot = public_messages.order(:id).pluck(:id, :conversation_id, :inbox_id, :source_id, :sender_id)
              media_snapshot = public_messages.order(:id).flat_map { |message| message.attachments.map { |a| [a.id, a.file.id, a.file.blob_id] } }
              deliver(order.first, cases.reverse) # retry before counterpart exists
              deliver(order.last, cases.reverse)
              order.reverse_each { |provider| deliver(provider) }

              expect(public_messages.count).to eq(expected_messages)
              expect(account.conversations.count).to eq(10)
              expect(account.contacts.count).to eq(10)
              expect(public_messages.order(:id).pluck(:id, :conversation_id, :inbox_id, :source_id, :sender_id) == first_snapshot).to be(true)
              media_after = public_messages.order(:id).flat_map { |message| message.attachments.map { |a| [a.id, a.file.id, a.file.blob_id] } }
              expect(media_after).to eq(media_snapshot)
              expect(account.conversations.pluck(:inbox_id).uniq).to eq([channels.fetch(principal).inbox.id])
              changed_fields = cases.each_with_index.flat_map do |row, index|
                contacts_before.fetch(index).keys.filter_map do |key|
                  current = row[:contact].reload.attributes[key]
                  previous = contacts_before.fetch(index)[key]
                  # Provider metadata may enrich attributes, but must never
                  # overwrite any pre-existing operator-owned value.
                  current = current.slice(*previous.keys) if key == 'additional_attributes'
                  "case #{index}: #{key}" if current != previous
                end
              end
              expect(changed_fields).to be_empty
              aliases_after = ContactInbox.where(contact_id: contact_ids).order(:id).pluck(:id, :contact_id, :inbox_id, :source_id)
              expect(aliases_after == aliases_before).to be(true), 'Existing contact aliases must be preserved exactly'

              cases.each do |row|
                conversation = account.conversations.where(contact: row[:contact]).sole
                expect(conversation.messages.where(message_type: :incoming).count).to eq(kinds(row).size)
                kinds(row).each do |kind|
                  message = conversation.messages.find_by(source_id: external_id(order.first, row, kind))
                  expect(message).not_to be_nil, "Missing canonical message for case #{row[:index]}"
                  expect(message).to have_attributes(sender_id: row[:contact].id, inbox_id: channels.fetch(principal).inbox.id)
                  ledger = WhatsappUnifiedMessage.find_by!(message: message)
                  expect(ledger.original_id == original_id(row, kind)).to be(true)
                  expect(ledger).to have_attributes(state: 'ready', whatsapp_inbox_link_id: link.id)
                  channels.each do |provider, channel|
                    identity = WhatsappMessageIdentity.find_by(inbox: channel.inbox, external_id: external_id(provider, row, kind))
                    expect(identity).not_to be_nil, "Missing #{provider} identity for case #{row[:index]}"
                    expect(identity.provider_message_id == original_id(row, kind)).to be(true)
                    expect(WhatsappUnifiedMessageAlias.find_by!(whatsapp_message_identity: identity).whatsapp_unified_message_id).to eq(ledger.id)
                  end
                  next if kind == :text

                  blob = message.attachments.sole.file.blob
                  expected_bytes = uploads.fetch(blob.key)
                  expect(blob.byte_size).to eq(expected_bytes.bytesize)
                  expect(blob.download).to eq(expected_bytes)
                  expect(blob.download).to eq(png_bytes) if kind == :image
                  expect(blob.download).to eq(ogg_bytes) if kind == :audio && order.first == :meta
                  expect(blob.content_type).to eq('audio/mpeg') if kind == :audio && order.first == :uno
                end
              end
              expected_downloads = cases.flat_map do |row|
                kinds(row).reject { |kind| kind == :text }.map { |kind| media_download_url(order.first, row, kind) }
              end
              expect(downloads == expected_downloads).to be(true), 'Only first-arrival media may be downloaded, once per media message'
              expect(uploads.size).to eq(expected_media)
              expect(ActiveStorage::Blob.service).to have_received(:upload).exactly(expected_media).times
              expect(uploads.values).to eq([png_bytes] * 10) unless replay_mode
              expect(ActiveStorage::Blob.count - blobs_before).to eq(expected_media)
              expect(Attachment.count - attachments_before).to eq(expected_media)
              expect(ActiveStorage::Attachment.count - stored_before).to eq(expected_media)
              expect(WhatsappUnifiedMessage.where(whatsapp_inbox_link: link).count).to eq(expected_messages)
              expect(WhatsappMessageIdentity.where(account: account).count).to eq(expected_messages * 2)
              expect(performed_jobs.map { |job| job[:job] }.uniq).to eq([Webhooks::WhatsappEventsJob])
              expect(link.reload.default_provider).to eq(default_provider)
              expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
            end
          end
        end
      end

      it 'rejects a bad Meta HMAC before any inbound job or download' do
        body = batch(:meta)
        headers = { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => 'sha256=synthetic-invalid' }
        expect do
          post "/webhooks/whatsapp/#{meta_channel.phone_number}", params: body, headers: headers
        end.not_to have_enqueued_job(Webhooks::WhatsappEventsJob)
        expect(response).to have_http_status(:unauthorized)
        expect(public_messages).to be_empty
        expect(account.conversations).to be_empty
        expect(downloads).to be_empty
        expect(uploads).to be_empty
      end

      it 'keeps unlinked inboxes on their independent legacy paths through retries' do
        %i[meta uno meta uno].each { |provider| deliver(provider) }
        expect(public_messages.count).to eq(expected_messages * 2)
        expect(account.conversations.count).to eq(20)
        expect(account.contacts.count).to eq(10)
        expect(WhatsappUnifiedMessage.joins(:whatsapp_inbox_link).where(whatsapp_inbox_links: { account_id: account.id })).to be_empty
        cases.each do |row|
          channels.each do |provider, channel|
            conversation = account.conversations.where(contact: row[:contact], inbox: channel.inbox).sole
            expected_ids = kinds(row).map { |kind| external_id(provider, row, kind) }
            expect(conversation.messages.where(message_type: :incoming).pluck(:source_id).sort == expected_ids.sort).to be(true)
          end
        end
        expect(downloads.size).to eq(expected_media * 2)
        expect(uploads.size).to eq(expected_media * 2)
        expect(performed_jobs.map { |job| job[:job] }.uniq).to eq([Webhooks::WhatsappEventsJob])
      end
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/ExpectInHook, Performance/CollectionLiteralInLoop
