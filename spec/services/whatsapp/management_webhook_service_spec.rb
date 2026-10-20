require 'rails_helper'

describe Whatsapp::ManagementWebhookService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:field) { 'business_capability_update' }
  let(:value) { { 'max_daily_conversations_per_business' => 1000, 'quality_rating' => 'GREEN' } }
  let(:entry) do
    { 'id' => channel.provider_config['business_account_id'], 'time' => 1_792_224_000,
      'changes' => [{ 'field' => field, 'value' => value }] }
  end
  let(:params) { { 'phone_number' => channel.phone_number, 'entry' => [entry] } }
  let(:service) { described_class.new(params: params) }

  before do
    channel
    Redis::Alfred.delete(channel.send(:reauthorization_required_key))
  end

  it 'records a WABA-scoped event without phone metadata for only the URL anchor' do
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    events = service.perform

    expect(events.length).to eq(1)
    expect(events.first).to have_attributes(account_id: channel.account_id, channel_id: channel.id, inbox_id: channel.inbox.id,
                                            state: 'recorded', truncated: false)
    expect(WhatsappManagementEvent.where(channel_id: other.id)).to be_empty
    expect(events.first.details).to eq(value)
    expect(events.first.expires_at).to be_within(5.seconds).of(7.days.from_now)
    expect(events.first.payload.dig('entry', 0, 'time')).to eq(entry['time'])
  end

  it 'accepts indifferent parameters and deduplicates reordered nested object keys' do
    value['nested'] = { 'z' => [{ 'b' => 2, 'a' => 1 }], 'a' => 0 }
    first = service.perform.first
    reordered = { value: value.merge('nested' => { 'a' => 0, 'z' => [{ 'a' => 1, 'b' => 2 }] }).to_a.reverse.to_h, field: field }
    entry['changes'] = [reordered]

    expect { described_class.new(params: params.with_indifferent_access).perform }.not_to change(WhatsappManagementEvent, :count)
    expect(service.perform.map(&:id)).to eq([first.id])
  end

  it 'creates separate receipts for different entry timestamps' do
    service.perform
    entry['time'] += 1
    expect { described_class.new(params: params).perform }.to change(WhatsappManagementEvent, :count).by(1)
  end

  it 'rejects a foreign WABA even if phone metadata matches' do
    entry['id'] = 'foreign-waba'
    value['metadata'] = { 'phone_number_id' => channel.provider_config['phone_number_id'] }
    expect(service.perform).to eq([])
    expect(WhatsappManagementEvent.count).to eq(0)
  end

  it 'rejects foreign phone metadata without rerouting to another channel' do
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    other.update!(provider_config: other.provider_config.merge('phone_number_id' => 'other-phone'))
    value['metadata'] = { 'phone_number_id' => 'other-phone' }
    expect { expect(service.perform).to eq([]) }.not_to change(WhatsappManagementEvent, :count)
  end

  it 'accepts matching metadata' do
    value['metadata'] = { 'phone_number_id' => channel.provider_config['phone_number_id'] }
    expect(service.perform.first.channel_id).to eq(channel.id)
  end

  it 'rejects mismatched root phone IDs even if metadata matches' do
    value['phone_number_id'] = 'foreign-phone'
    value['metadata'] = { 'phone_number_id' => channel.provider_config['phone_number_id'] }
    expect(service.perform).to eq([])
  end

  it 'accepts matching root phone IDs and formatted display numbers' do
    value['phone_number_id'] = channel.provider_config['phone_number_id']
    value['display_phone_number'] = channel.phone_number.chars.join(' ')
    expect(service.perform.first.channel_id).to eq(channel.id)
  end

  it 'rejects foreign root display numbers without trying another account or suffix match' do
    value['display_phone_number'] = "999#{channel.phone_number.last(9)}"
    expect(service.perform).to eq([])
  end

  it 'accepts an exact full root display number without a phone ID' do
    value['display_phone_number'] = channel.phone_number
    expect(service.perform.first.channel_id).to eq(channel.id)
  end

  it 'does not match phone suffixes, business-scoped user IDs or an absent URL anchor' do
    [channel.phone_number.last(9), 'BSUID', nil].each do |anchor|
      params['phone_number'] = anchor
      expect(described_class.new(params: params).perform).to eq([])
    end
    expect(WhatsappManagementEvent.count).to eq(0)
  end

  it 'rejects non-cloud channels' do
    channel.update!(provider: 'unoapi')
    expect(service.perform).to eq([])
  end

  it 'rejects an anchor without configured WABA identity' do
    channel.update!(provider_config: channel.provider_config.except('business_account_id'))
    expect(service.perform).to eq([])
  end

  it 'rejects suspended accounts including security events' do
    channel.account.update!(status: :suspended)
    entry['changes'].first['field'] = 'security'
    expect { expect(service.perform).to eq([]) }.not_to change(WhatsappManagementEvent, :count)
  end

  it 'continues to audit security and account alerts on channels requiring reauthorization' do
    Redis::Alfred.set(channel.send(:reauthorization_required_key), true)
    %w[security account_alerts].each do |audit_field|
      entry['changes'].first['field'] = audit_field
      expect(described_class.new(params: params).perform.first).to have_attributes(field: audit_field, state: 'recorded')
    end
  end

  it 'records template events for review without invalidation or sync while reauthorization is required' do
    Redis::Alfred.set(channel.send(:reauthorization_required_key), true)
    entry['changes'].first['field'] = 'message_template_status_update'
    original_timestamp = channel.reload.message_templates_last_updated
    expect do
      expect(service.perform.first).to have_attributes(state: 'review', reason: 'reauthorization_required')
    end.not_to have_enqueued_job(Channels::Whatsapp::TemplatesSyncJob)
    expect(channel.reload.message_templates_last_updated).to eq(original_timestamp)
  end

  it 'retains unknown future administrative fields safely' do
    entry['changes'].first['field'] = 'future_meta_field'
    expect(service.perform.first).to have_attributes(field: 'future_meta_field', state: 'recorded', reason: 'unknown_field')
  end

  it 'leaves messaging and calls to their existing handlers' do
    (Whatsapp::WebhookFields::MESSAGING + %w[calls]).each do |other_field|
      entry['changes'].first['field'] = other_field
      expect(described_class.new(params: params).perform).to eq([])
    end
  end

  it 'records group fields as audit-only receipts without legacy domain mutations' do
    Whatsapp::WebhookFields::GROUP.each do |group_field|
      entry['changes'].first['field'] = group_field
      expect(described_class.new(params: params).perform.first).to have_attributes(field: group_field, state: 'recorded')
    end
  end

  it 'ignores history by default without retaining bodies, creating domain data or jobs' do
    value.merge!('contacts' => [{ 'name' => 'Private Name' }], 'messages' => [{ 'timestamp' => '1792224000', 'text' => 'Private' }])
    expect(Contact).not_to receive(:create!)
    expect(Message).not_to receive(:create!)
    expect(Attachment).not_to receive(:create!)
    counts = [Contact.count, Message.count, Attachment.count, Conversation.count]

    expect do
      entry['changes'].first['field'] = 'history'
      event = described_class.new(params: params).perform.first
      expect(event).to have_attributes(state: 'recorded', reason: 'history_ignored', payload: {})
      expect(event.details).to include('contacts_count' => 1, 'messages_count' => 1)
    end.not_to have_enqueued_job
    expect([Contact.count, Message.count, Attachment.count, Conversation.count]).to eq(counts)
  end

  it 'retains bounded sanitized app contact state for user review regardless of message history settings' do
    entry['changes'].first['field'] = 'smb_app_state_sync'
    value['contacts'] = [{ 'name' => 'Private Name', 'access_token' => 'secret-token' }]
    counts = [Contact.count, Message.count, Attachment.count, Conversation.count]
    expect do
      event = service.perform.first
      expect(event).to have_attributes(state: 'pending_import', reason: 'user_choice_required')
      expect(event.payload.to_json).to include('Private Name', '[FILTERED]')
      expect(event.payload.to_json).not_to include('secret-token')
      expect(event.details).to include('contacts_count' => 1)
    end.not_to have_enqueued_job
    expect([Contact.count, Message.count, Attachment.count, Conversation.count]).to eq(counts)
  end

  it 'marks oversized app contact state for review without claiming an importable payload' do
    entry['changes'].first['field'] = 'smb_app_state_sync'
    value['contacts'] = [{ 'name' => 'a' * WhatsappManagementEvent::MAX_PAYLOAD_BYTES }]
    expect(service.perform.first).to have_attributes(state: 'review', reason: 'payload_too_large', truncated: true)
  end

  it 'counts official state_sync contact records including removals without importing contacts' do
    entry['changes'].first['field'] = 'smb_app_state_sync'
    value.replace('state_sync' => [
                    { 'type' => 'contact', 'action' => 'add', 'contact' => { 'full_name' => 'Private', 'phone_number' => '16505551234' } },
                    { 'type' => 'contact', 'action' => 'remove', 'contact' => { 'phone_number' => '16505551235' } },
                    { 'type' => 'future' }
                  ])
    original_counts = [Contact.count, Message.count, Conversation.count]
    event = service.perform.sole
    expect(event).to have_attributes(state: 'pending_import', reason: 'user_choice_required')
    expect(event.summary[:details]).to include('contacts_count' => 2)
    expect([Contact.count, Message.count, Conversation.count]).to eq(original_counts)
  end

  it 'records official history refusal as lifecycle control regardless of the import setting' do
    entry['changes'].first['field'] = 'history'
    value.replace('history' => [{ 'errors' => [{ 'code' => 2_593_109, 'title' => 'History sync is turned off' }] }])
    [true, false].each do |ignored|
      channel.update!(provider_config: channel.provider_config.merge('ignore_history_messages' => ignored))
      entry['time'] += 1
      expect do
        event = described_class.new(params: params).perform.sole
        expect(event).to have_attributes(state: 'recorded', reason: nil, payload: {})
        expect(event.summary[:details]).to include('status' => 'DISABLED')
      end.not_to have_enqueued_job(Whatsapp::ImportHistoryJob)
    end
  end

  it 'keeps history ignored unless the setting is explicitly Boolean false' do
    entry['changes'].first['field'] = 'history'
    [nil, 'false', 0, 'malformed', true].each do |setting|
      channel.update!(provider_config: channel.provider_config.merge('ignore_history_messages' => setting))
      entry['time'] += 1
      event = described_class.new(params: params).perform.first
      expect(event).to have_attributes(state: 'recorded', reason: 'history_ignored', payload: {})
    end
  end

  context 'when history review is explicitly enabled' do
    let(:field) { 'history' }
    let(:now) { Time.zone.parse('2026-10-17 12:00:00') }
    let(:messages) do
      [
        { 'timestamp' => now.to_i.to_s, 'text' => { 'body' => 'recent-body' } },
        { 'timestamp' => (now - 7.days).to_i.to_s, 'text' => { 'body' => 'boundary-body' } },
        { 'timestamp' => (now - 8.days).to_i.to_s, 'text' => { 'body' => 'old-body' } },
        { 'timestamp' => (now + 1.day).to_i.to_s, 'text' => { 'body' => 'future-body' } },
        { 'timestamp' => 'invalid', 'text' => { 'body' => 'invalid-body' } }
      ]
    end
    let(:value) do
      { 'messaging_product' => 'whatsapp', 'history' => [
        { 'metadata' => { 'phase' => 0, 'progress' => 50, 'chunk_order' => 1 },
          'threads' => [{ 'id' => 'thread-id', 'messages' => messages }] }
      ] }
    end

    before do
      channel.update!(provider_config: channel.provider_config.merge('ignore_history_messages' => false))
    end

    it 'filters before persistence using the received time and queues automatic seven-day import' do
      travel_to(now) do
        entry['time'] = (now - 60.days).to_i
        expect do
          event = service.perform.first
          expect(event).to have_attributes(state: 'pending_import', reason: 'automatic_import_pending')
          retained = event.payload.dig('entry', 0, 'changes', 0, 'value', 'history', 0)
          expect(retained['metadata']).to eq('phase' => 0, 'progress' => 50, 'chunk_order' => 1)
          expect(retained.dig('threads', 0, 'messages').length).to eq(2)
          expect(event.payload.to_json).to include('recent-body', 'boundary-body')
          expect(event.payload.to_json).not_to include('old-body', 'invalid-body', 'future-body')
          expect(event.details).to include('messages_count' => 5, 'kept_messages_count' => 2,
                                           'dropped_messages_count' => 3, 'invalid_messages_count' => 1)
        end.not_to change(Message, :count)
      end
    end

    it 'clamps the configured age to at least one day' do
      channel.update!(provider_config: channel.provider_config.merge('history_max_age_days' => 0))
      travel_to(now) do
        event = service.perform.first
        expect(event.details['kept_messages_count']).to eq(1)
        expect(event.payload.to_json).not_to include('boundary-body', 'old-body')
      end
    end

    it 'filters official top-level media follow-ups before retaining them with the same link snapshot' do
      value.replace('messages' => messages)
      travel_to(now) do
        event = service.perform.sole
        expect(event).to have_attributes(state: 'pending_import', reason: 'automatic_import_pending')
        expect(event.payload.dig('entry', 0, 'changes', 0, 'value', 'messages').size).to eq(2)
        expect(event.payload.to_json).not_to include('old-body', 'future-body', 'invalid-body')
        expect(event.details).to include('messages_count' => 5, 'kept_messages_count' => 2, 'history_link_id' => nil)
      end
    end

    it 'clamps the configured age to at most 3650 days' do
      channel.update!(provider_config: channel.provider_config.merge('history_max_age_days' => 99_999))
      messages.replace([{ 'timestamp' => (now - 3650.days).to_i.to_s, 'text' => { 'body' => 'kept-decade' } },
                        { 'timestamp' => (now - 3651.days).to_i.to_s, 'text' => { 'body' => 'old-decade' } }])
      travel_to(now) do
        event = service.perform.first
        expect(event.payload.to_json).to include('kept-decade')
        expect(event.payload.to_json).not_to include('old-decade')
      end
    end

    it 'removes unrecognized envelope locations instead of storing unfiltered historical bodies' do
      value['unrecognized_messages'] = [{ 'timestamp' => '1', 'body' => 'old-in-unknown-location' }]
      travel_to(now) do
        expect(service.perform.first.payload.to_json).not_to include('old-in-unknown-location')
      end
    end

    it 'retains only summary for unknown formats and does not fall back to raw history' do
      value.replace('history' => { 'messages' => [{ 'body' => 'unknown-old-body' }] }, 'contacts' => [{ 'name' => 'Private' }])
      event = service.perform.first
      expect(event).to have_attributes(state: 'review', reason: 'unsupported_history_format', payload: {})
      expect(event.details).to include('contacts_count' => 1)
    end

    it 'rejects malformed nested thread formats without preserving any partial raw history' do
      value['history'].first['threads'] << { 'messages' => 'unknown-old-body' }
      travel_to(now) do
        expect(service.perform.first).to have_attributes(state: 'review', reason: 'unsupported_history_format', payload: {})
      end
    end

    it 'marks oversized filtered history for review rather than making an empty payload importable' do
      messages.first['text']['body'] = 'a' * WhatsappManagementEvent::MAX_PAYLOAD_BYTES
      travel_to(now) do
        event = service.perform.first
        expect(event).to have_attributes(state: 'review', reason: 'payload_too_large', truncated: true)
        expect(event.payload.to_json.bytesize).to be <= WhatsappManagementEvent::MAX_PAYLOAD_BYTES
      end
    end
  end

  it 'invalidates the template timestamp and queues one existing sync job only on the first delivery' do
    entry['changes'].first['field'] = 'message_template_status_update'
    original_config = channel.provider_config.deep_dup
    expect { service.perform }.to have_enqueued_job(Channels::Whatsapp::TemplatesSyncJob).with(channel).once
    expect(channel.reload.message_templates_last_updated).to be_nil
    expect(channel.provider_config).to eq(original_config)
    expect(WhatsappManagementEvent.last.state).to eq('processed')

    channel.update!(message_templates_last_updated: Time.current)
    expect { service.perform }.not_to have_enqueued_job(Channels::Whatsapp::TemplatesSyncJob)
    expect(channel.reload.message_templates_last_updated).to be_present
  end

  it 'rolls back the receipt and invalidation when enqueue fails so a retry can apply them' do
    entry['changes'].first['field'] = 'message_template_quality_update'
    original_timestamp = channel.reload.message_templates_last_updated
    allow(Channels::Whatsapp::TemplatesSyncJob).to receive(:perform_later).and_raise(StandardError, 'queue unavailable')
    expect { service.perform }.to raise_error(StandardError, 'queue unavailable')
    expect(WhatsappManagementEvent.count).to eq(0)
    expect(channel.reload.message_templates_last_updated).to eq(original_timestamp)
  end

  it 'preserves whitelisted capability snapshots and excludes free-form PII from summaries' do
    value.merge!('current_limit' => 250, 'status' => 'APPROVED', 'name' => 'Private Name', 'email' => 'private@example.test')
    event = service.perform.first
    expect(event.details).to include('current_limit' => 250, 'quality_rating' => 'GREEN', 'status' => 'APPROVED')
    expect(event.summary[:details]).not_to include('name', 'email')
    expect(event.payload.to_json).to include('private@example.test')
  end

  it 'preserves Meta tier capability snapshots without accepting arbitrary strings or PII' do
    value['max_daily_conversations_per_business'] = 'TIER_2K'
    value['current_limit'] = 'private@example.test'
    event = service.perform.first
    expect(event.details).to include('max_daily_conversations_per_business' => 'TIER_2K')
    expect(event.summary[:details]).not_to include('current_limit')
  end

  it 'records unknown future fields even when their value is not an object' do
    entry['changes'] = [{ 'field' => 'future_meta_field', 'value' => ['future-format'] }]
    expect(service.perform.first).to have_attributes(state: 'recorded', reason: 'unknown_field')
  end

  it 'uses the configured Rails filter recursively and never logs raw webhook contents' do
    value.merge!('access_token' => 'secret-token', 'nested' => { 'api_key' => 'secret-key', 'password' => 'secret-password' })
    expect(Rails.logger).not_to receive(:info).with(include('secret-token'))
    event = service.perform.first
    retained = event.payload.dig('entry', 0, 'changes', 0, 'value')
    expect(retained['access_token']).to eq('[FILTERED]')
    expect(retained['nested'].values).to eq(['[FILTERED]', '[FILTERED]'])
    expect(event.payload.to_json).not_to include('secret-token', 'secret-key', 'secret-password')
  end

  it 'caps oversized UTF-8 payloads with valid JSON and an explicit truncation flag' do
    value.merge!('large' => 'á' * WhatsappManagementEvent::MAX_PAYLOAD_BYTES, 'access_token' => 'secret-token')
    event = service.perform.first
    expect(event.truncated).to be(true)
    expect(event.payload).to include('truncated' => true)
    expect(event.payload.to_json.bytesize).to be <= WhatsappManagementEvent::MAX_PAYLOAD_BYTES
    expect(event.payload.to_json).not_to include('secret-token')
    expect(event.details).to include('quality_rating' => 'GREEN')
    expect(service.perform.first.id).to eq(event.id)
  end
end
