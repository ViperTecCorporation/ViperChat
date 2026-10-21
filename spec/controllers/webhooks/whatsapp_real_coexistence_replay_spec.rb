require 'uri'

# Private input is opt-in, never a fixture. Guard before rails_helper can load a schema.
if ENV['WHATSAPP_REAL_COEX_REPLAY'].to_s != ''
  database = ENV['DATABASE_URL'].to_s.empty? ? ENV.fetch('POSTGRES_DATABASE', nil) : URI(ENV.fetch('DATABASE_URL')).path.delete_prefix('/')
  abort('Real coexistence replay requires its isolated test database') unless
    ENV['RAILS_ENV'] == 'test' && database == 'viperchat_meta_real_coex_test'
end

require 'rails_helper'

# Only routing metadata is remapped. Message IDs, participants, content and timestamps
# remain captured values. Assertions deliberately expose booleans/counts, not private data.
# rubocop:disable RSpec/ExpectInHook
RSpec.describe 'Private real paired coexistence HTTP replay', type: :request do
  let(:capture) { JSON.parse(File.read(ENV.fetch('WHATSAPP_REAL_COEX_REPLAY'))) }
  let(:events) { capture.fetch('events').sort_by { |row| Time.iso8601(row.fetch('received_at')) } }
  let(:account) { create(:account) }
  let(:secret) { 'isolated-real-coexistence-test-secret' }
  let(:unexpected_contact_positions) { [] }
  let(:message_kinds) { %w[messages message_echoes] }
  let(:meta_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              provider_config: { 'api_key' => 'synthetic', 'phone_number_id' => 'local-meta-phone',
                                                 'business_account_id' => 'local-waba', 'app_secret' => secret },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno_channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              provider_config: { 'api_key' => 'synthetic', 'phone_number_id' => 'local-uno-phone',
                                                 'url' => 'https://uno.invalid' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:channels) { { 65 => meta_channel, 1 => uno_channel } }
  let(:captured_channels) { capture.fetch('channels').select { |row| channels.key?(row.fetch('inbox_id')) } }
  let(:seeded_contacts) do
    capture.fetch('contacts').each_with_object({}) do |row, result|
      aliases = row.fetch('aliases').select { |inbox_id, _| channels.key?(inbox_id) }
      # Keep known contact identities even when no pair alias was captured.
      # In particular, never import their aliases from the unrelated inbox 18.
      contact = create(:contact, account: account, name: "Preserved replay contact #{result.size}",
                                 phone_number: row['phone_number'].presence, bsuid: row['bsuid'].presence)
      aliases.each do |inbox_id, source_id|
        create(:contact_inbox, contact: contact, inbox: channels.fetch(inbox_id).inbox, source_id: source_id)
      end
      result[row.fetch('id')] = contact
    end
  end
  let(:message_events) do
    events.flat_map do |row|
      channel = replay_channel(row)
      row.fetch('payload').fetch('entry').flat_map do |entry|
        entry.fetch('changes').flat_map do |change|
          value = change.fetch('value')
          message_kinds.flat_map do |kind|
            Array(value[kind]).map do |message|
              original = if channel.provider == 'whatsapp_cloud'
                           Whatsapp::MetaMessageIdAdapter.parse(message.fetch('id'))&.fetch('provider_message_id')
                         else
                           message['provider_message_id']
                         end
              raise 'Private capture contains an unrecognized correlation ID' if original.blank?

              { key: [original, kind == 'message_echoes' ? 'outgoing' : 'incoming'],
                channel: channel, message: message, position: events.index(row) + 1 }
            end
          end
        end
      end
    end
  end
  let(:groups) { message_events.group_by { |row| row.fetch(:key) } }
  let(:public_messages) { account.messages.where(message_type: %i[incoming outgoing], private: false) }

  around do |example|
    if ENV['WHATSAPP_REAL_COEX_REPLAY'].blank?
      example.run
      next
    end

    network = WebMock::Config.instance.allow_net_connect
    localhost = WebMock::Config.instance.allow_localhost
    adapter = ActiveJob::Base.queue_adapter
    loggers = [Rails.logger, ActiveRecord::Base.logger, ActiveJob::Base.logger, ActionController::Base.logger].compact.uniq
    levels = loggers.index_with(&:level)
    loggers.each { |logger| logger.level = Logger::UNKNOWN + 1 }
    ActiveJob::Base.queue_adapter = :test
    WebMock.disable_net_connect!(allow_localhost: false)
    travel_to(events.map { |row| Time.iso8601(row.fetch('received_at')) }.max + 1.minute) { example.run }
  ensure
    if levels
      clear_enqueued_jobs
      clear_performed_jobs
      levels.each { |logger, level| logger.level = level }
      ActiveJob::Base.queue_adapter = adapter
      WebMock::Config.instance.allow_net_connect = network
      WebMock::Config.instance.allow_localhost = localhost
    end
  end

  before do
    skip 'Set WHATSAPP_REAL_COEX_REPLAY to a private capture file' if ENV['WHATSAPP_REAL_COEX_REPLAY'].blank?
    raise 'Unexpected replay database' unless ActiveRecord::Base.connection.current_database == 'viperchat_meta_real_coex_test'

    # Refuse even previously stubbed HTTP; only Rails' in-process request path is used.
    stub_request(:any, /.*/).to_raise(StandardError.new('External HTTP forbidden in private replay'))
    expect(Down).not_to receive(:download)
    %i[upload download delete delete_prefixed open].each do |operation|
      expect(ActiveStorage::Blob.service).not_to receive(operation)
    end
    expect(events.size).to eq(32)
    expect(message_events.size).to eq(18)
    expect(groups.size).to eq(9)
    expect(message_events.all? { |row| row[:message]['type'] == 'text' }).to be(true)
    expect(groups.values.all? { |rows| rows.map { |row| row[:channel].provider }.sort == %w[unoapi whatsapp_cloud] }).to be(true)
    expect(message_events.count { |row| row[:key].last == 'outgoing' && row[:channel] == meta_channel }).to eq(3)
    expect(message_events.count { |row| row[:key].last == 'outgoing' && row[:channel] == uno_channel }).to eq(3)
    seeded_contacts
    expect(account.contacts.count).to eq(seeded_contacts.size)
    clear_enqueued_jobs
  end

  # These helpers implement the repeated real HTTP transport, not fabricated payloads.
  def replay_channel(row)
    # These two routing numbers intentionally normalize to the same Brazilian mobile.
    # Preserve the captured route to identify the provider; normalization is for peers.
    phone = row.fetch('payload').fetch('phone_number').to_s.delete_prefix('+')
    captured = captured_channels.find { |channel| channel.fetch('phone_number').delete_prefix('+') == phone }
    raise 'Private capture references a channel outside the selected pair' unless captured

    channels.fetch(captured.fetch('inbox_id'))
  end

  # Keep authenticated transport and private assertions together for review.
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def deliver_real_event(row)
    channel = replay_channel(row)
    # controller/action/whatsapp are Rails parameter-wrapper artifacts, not wire fields.
    payload = row.fetch('payload').slice('object', 'entry').deep_dup
    payload.fetch('entry').each do |entry|
      entry['id'] = 'local-waba'
      entry.fetch('changes').each do |change|
        metadata = change.fetch('value').fetch('metadata')
        metadata['phone_number_id'] = channel.provider_config.fetch('phone_number_id')
        metadata['display_phone_number'] = channel.phone_number.delete_prefix('+')
      end
    end
    body = payload.to_json
    headers = { 'CONTENT_TYPE' => 'application/json' }
    if channel.provider == 'unoapi'
      headers['Authorization'] = channel.provider_config.fetch('webhook_verify_token')
    else
      headers['X-Hub-Signature-256'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    end
    contacts_before = account.contacts.count
    perform_enqueued_jobs(only: [Webhooks::WhatsappEventsJob]) do
      post "/webhooks/whatsapp/#{channel.phone_number}", params: body, headers: headers
    end
    unexpected_contact_positions << (events.index(row) + 1) if account.contacts.count > contacts_before
    expect(response.status).to eq(200)
  rescue StandardError
    # Domain exceptions can contain private participant values. Never print them.
    raise 'Private replay request failed; inspect locally without logging the payload', cause: nil
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def canonical_snapshot(link)
    WhatsappUnifiedMessage.where(whatsapp_inbox_link: link).order(:id).map do |ledger|
      message = ledger.message
      [ledger.id, ledger.original_id, ledger.direction, message&.id, message&.source_id,
       message&.conversation_id, message&.inbox_id, message&.sender_id, message&.content]
    end
  end

  def alias_failure_context(identity, row, link)
    return 'Identity missing' unless identity

    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: identity, partner_inbox: link.partner_for(row[:channel].inbox)).perform
    reasons = WhatsappUnifiedEvent.where(whatsapp_message_identity: identity).distinct.pluck(:reason)
    "Capture position #{row[:position]} (#{row[:channel].provider}, #{row[:key].last}); " \
      "correlation=#{comparison[:status]}; pending_reasons=#{reasons.join(',')}"
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def assert_real_bubbles(link, principal)
    expect(public_messages.count).to eq(9)
    ledgers = WhatsappUnifiedMessage.where(whatsapp_inbox_link: link)
    expect(ledgers.count).to eq(9)
    expect(public_messages.pluck(:inbox_id).uniq == [principal.inbox.id]).to be(true)
    expect(account.contacts.count).to(
      eq(seeded_contacts.size), "Unexpected contacts at chronological capture positions #{unexpected_contact_positions.inspect}"
    )
    expect(account.contacts.order(:id).pluck(:id) == seeded_contacts.values.map(&:id).sort).to be(true)
    groups.each do |(original, direction), rows|
      ledger = ledgers.find_by(original_id: original, direction: direction)
      expect(ledger.present? && ledger.state == 'ready' && ledger.message.present?).to be(true)
      next unless ledger&.message

      message = ledger.message
      expect(!message.private? && message.message_type == direction).to be(true)
      expect(rows.all? { |row| message.content == row[:message].dig('text', 'body') }).to be(true)
      rows.each do |row|
        identity = WhatsappMessageIdentity.find_by(inbox: row[:channel].inbox, external_id: row[:message].fetch('id'))
        expect(identity.present? && identity.provider_message_id == original).to be(true)
        mapped = identity && WhatsappUnifiedMessageAlias.find_by(whatsapp_message_identity: identity)
        expect(mapped.present? && mapped.whatsapp_unified_message_id == ledger.id)
          .to(be(true), alias_failure_context(identity, row, link))
      end
      # A deduplicated production message need only retain one provider's public ID.
      sources = rows.map { |row| row[:message].fetch('id') }
      captured = capture.fetch('messages').select { |item| sources.include?(item['source_id']) }
      expected_contacts = captured.map { |item| seeded_contacts[item.fetch('contact_id')]&.id }.uniq
      expect(expected_contacts.size == 1 && expected_contacts.first.present?).to be(true)
      expect(expected_contacts.include?(message.conversation.contact_id)).to be(true)
    end
    expect([Attachment.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count]).to eq([0, 0, 0])
    expect(performed_jobs.map { |job| job[:job] }.uniq).to eq([Webhooks::WhatsappEventsJob])
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  orders = %i[chronological reverse]
  [65, 1].each do |principal_id|
    orders.each do |order|
      it "keeps nine real bubbles with principal #{principal_id}, #{order} delivery and two original-order retries", :aggregate_failures do
        principal = channels.fetch(principal_id)
        link = WhatsappInboxLink.create!(account: account, primary_inbox: principal.inbox,
                                         secondary_inbox: channels.fetch(principal_id == 65 ? 1 : 65).inbox,
                                         default_provider: principal.provider, enabled: true)
        # Activation stamps Time.current on creation; move only this test link's
        # cutoff before the captured messages without changing their timestamps.
        link.update!(activated_at: Time.at(message_events.map { |row| row[:message].fetch('timestamp').to_i }.min).utc - 1.day)
        sequence = order == :reverse ? events.reverse : events
        sequence.each { |row| deliver_real_event(row) }
        assert_real_bubbles(link, principal)
        preserved = canonical_snapshot(link)
        2.times do
          events.each { |row| deliver_real_event(row) }
          assert_real_bubbles(link, principal)
          expect(canonical_snapshot(link) == preserved).to be(true)
        end
      end
    end
  end
end
# rubocop:enable RSpec/ExpectInHook
