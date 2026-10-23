require 'rails_helper'

RSpec.describe Voip::SyncHistoryService do
  let(:account) { create(:account) }
  let(:service) do
    VoipService.create!(account: account, name: 'Central', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test',
                        credentials: { integration_provider: 'viperconnect', webhook_source_instance_id: 'pbx-1',
                                       history_api_url: 'https://voice.example.test', history_api_token: 'test-secret',
                                       history_company_id: 'company-1' })
  end
  let(:event) do
    { 'schema_version' => 1, 'event_id' => 'event-3', 'event_type' => 'call.updated', 'occurred_at' => '2026-10-22T12:00:00Z',
      'source_instance_id' => 'pbx-1', 'call_id' => 'call-1', 'revision' => 3,
      'call' => { 'direction' => 'inbound', 'state' => 'completed', 'started_at' => '2026-10-22T12:00:00Z', 'participants' => [] } }
  end
  let(:page) { { 'items' => [{ 'sequence' => 3, 'webhook_event' => event }], 'nextCursor' => 'opaque-checkpoint', 'hasMore' => false } }
  let(:client) { instance_double(Voip::WebhookHistoryClient, fetch_webhook_events: page) }

  before { allow(Voip::WebhookHistoryClient).to receive(:new).with(service).and_return(client) }

  it 'commits canonical inbox events and encrypted checkpoints atomically and deduplicates webhook overlap' do
    Voip::ReceiveProviderEventService.new(service: service, payload: event).perform
    expect { described_class.new(service: service).perform }.not_to change(VoipProviderEvent, :count)
    state = service.reload.history_sync_state
    expect([state.state, state.cursor]).to eq(['caught_up', 'opaque-checkpoint'])
    expect(state.encrypted_cursor).not_to include('opaque-checkpoint')
    expect(state.public_payload).not_to have_key('cursor')
    expect(state.last_success_at).to be_present
  end

  it 'rolls back all staged events and keeps the old checkpoint when a later event conflicts' do
    page['items'] << { 'sequence' => 4, 'webhook_event' => event.merge('revision' => 4) }
    described_class.new(service: service).perform
    state = service.reload.history_sync_state
    expect(VoipProviderEvent.count).to eq(0)
    expect(state.cursor).to be_nil
    expect([state.state, state.last_error_code]).to eq(%w[revision_conflict revision_conflict])
  end

  it 'keeps committed events discoverable after Redis fails before enqueue and resumes from the saved cursor' do
    allow(Voip::ProcessProviderEventJob).to receive(:perform_later).and_raise(IOError, 'queue unavailable')
    described_class.new(service: service).perform
    expect(VoipProviderEvent.pending.count).to eq(1)
    expect(service.reload.history_sync_state.cursor).to eq('opaque-checkpoint')
    described_class.request(service: service)
    described_class.new(service: service).perform
    expect(client).to have_received(:fetch_webhook_events).with(cursor: 'opaque-checkpoint')
    expect(VoipProviderEvent.count).to eq(1)
  end

  it 'coalesces concurrent workers and expires a crashed lease without advancing the cursor' do
    allow(client).to receive(:fetch_webhook_events) do
      described_class.new(service: service).perform
      raise 'synthetic crash'
    end
    expect { described_class.new(service: service).perform }.to raise_error('synthetic crash')
    expect(client).to have_received(:fetch_webhook_events).once
    expect(service.reload.history_sync_state.cursor).to be_nil
    service.history_sync_state.update!(lease_expires_at: 1.second.ago)
    allow(client).to receive(:fetch_webhook_events).and_return(page)
    described_class.new(service: service).perform
    expect(service.reload.history_sync_state.state).to eq('caught_up')
  end

  it 'discards an in-flight page when the company configuration changes' do
    allow(client).to receive(:fetch_webhook_events) do
      other = VoipService.find(service.id)
      other.credentials = other.credentials.merge('history_company_id' => 'company-2')
      other.save!
      page
    end
    described_class.new(service: service).perform
    expect(VoipProviderEvent.count).to eq(0)
    state = service.reload.history_sync_state
    expect([state.cursor, state.reset_requested, state.state]).to eq([nil, true, 'pending'])
  end

  { Voip::ServiceHistoryClient::InvalidCursorError => 'invalid_cursor',
    Voip::ServiceHistoryClient::ScopeChangedError => 'scope_changed',
    Voip::ServiceHistoryClient::AuthenticationError => 'authentication_failed' }.each do |error, state|
    it "blocks automatic retries on #{state} without deleting the prior checkpoint" do
      described_class.new(service: service).perform
      described_class.request(service: service)
      allow(client).to receive(:fetch_webhook_events).and_raise(error)
      described_class.new(service: service).perform
      checkpoint = service.reload.history_sync_state
      expect([checkpoint.state, checkpoint.cursor]).to eq([state, 'opaque-checkpoint'])
      described_class.new(service: service).perform
      expect(client).to have_received(:fetch_webhook_events).twice
    end
  end

  it 'recovers an expired cursor with a retained snapshot and records the unrecoverable-gap warning' do
    described_class.new(service: service).perform
    described_class.request(service: service)
    allow(client).to receive(:fetch_webhook_events).and_raise(Voip::ServiceHistoryClient::CursorExpiredError)
    described_class.new(service: service).perform
    state = service.reload.history_sync_state
    expect([state.cursor, state.reset_requested, state.gap_detected]).to eq(['opaque-checkpoint', true, true])
    state.update!(next_attempt_at: 1.second.ago)
    page['nextCursor'] = 'new-checkpoint'
    allow(client).to receive(:fetch_webhook_events).and_return(page)
    described_class.new(service: service).perform
    expect(client).to have_received(:fetch_webhook_events).with(cursor: nil).twice
    expect(service.reload.history_sync_state.cursor).to eq('new-checkpoint')
    expect(service.history_sync_state).to be_gap_detected
  end

  it 'preserves the old cursor during an explicit reset until a fresh page succeeds' do
    described_class.new(service: service).perform
    admin = create(:user, account: account, role: :administrator)
    described_class.request(service: service, reset_cursor: true, requested_by: admin)
    allow(client).to receive(:fetch_webhook_events).and_raise(Voip::ServiceHistoryClient::ConnectionError)
    described_class.new(service: service).perform
    state = service.reload.history_sync_state
    expect([state.cursor, state.reset_requested, state.state]).to eq(['opaque-checkpoint', true, 'retry'])
    expect(state.next_attempt_at).to be > Time.current
    expect(state.last_requested_by_id).to eq(admin.id)
    expect(state.last_reset_at).to be_present
  end

  it 'requires an explicit company before any automatic fetch and keeps other service checkpoints isolated' do
    service.credentials = service.credentials.except('history_company_id')
    service.save!
    described_class.new(service: service).perform
    expect(client).not_to have_received(:fetch_webhook_events)
    expect(service.reload.history_sync_state.state).to eq('configuration_required')
    expect(VoipProviderEvent.count).to eq(0)
  end

  it 'continues paginated work after committing each page and never advances over an uncommitted page' do
    page['hasMore'] = true
    last_page = { 'items' => [], 'nextCursor' => 'caught-up-cursor', 'hasMore' => false }
    allow(client).to receive(:fetch_webhook_events).and_return(page, last_page)
    expect { described_class.new(service: service).perform }.to have_enqueued_job(Voip::SyncHistoryJob).with(service.id)
    expect(service.reload.history_sync_state).to have_more
    described_class.new(service: service).perform
    expect(client).to have_received(:fetch_webhook_events).with(cursor: 'opaque-checkpoint')
    expect(service.reload.history_sync_state.cursor).to eq('caught-up-cursor')
    expect(service.history_sync_state.state).to eq('caught_up')
    expect(VoipProviderEvent.count).to eq(1)
  end

  it 'keeps independent company checkpoints and events even when public event ids are identical' do
    other = VoipService.create!(account: account, name: 'Other', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test',
                                credentials: service.credentials.merge('history_company_id' => 'company-2'))
    other_page = page.merge('nextCursor' => 'other-company-cursor')
    other_client = instance_double(Voip::WebhookHistoryClient, fetch_webhook_events: other_page)
    allow(Voip::WebhookHistoryClient).to receive(:new).with(other).and_return(other_client)
    described_class.new(service: service).perform
    described_class.new(service: other).perform
    expect(service.reload.history_sync_state.cursor).to eq('opaque-checkpoint')
    expect(other.reload.history_sync_state.cursor).to eq('other-company-cursor')
    expect(VoipProviderEvent.where(voip_service: service).count).to eq(1)
    expect(VoipProviderEvent.where(voip_service: other).count).to eq(1)
  end

  it 'blocks an unreadable encrypted checkpoint without fetching history or logging the ciphertext' do
    described_class.new(service: service).perform
    state = service.reload.history_sync_state
    state.update!(encrypted_cursor: 'damaged-ciphertext')
    described_class.request(service: service)
    described_class.new(service: service).perform
    expect(state.reload.state).to eq('invalid_cursor')
    expect(state.encrypted_cursor).to eq('damaged-ciphertext')
    expect(client).to have_received(:fetch_webhook_events).once
  end

  it 'shows current provider and configuration changes rather than a stale caught-up checkpoint' do
    described_class.new(service: service).perform
    expect(service.reload.history_sync_payload['state']).to eq('caught_up')
    service.credentials = service.credentials.merge('history_company_id' => 'company-2')
    service.save!
    expect(service.history_sync_payload['state']).to eq('pending')
    service.credentials = service.credentials.merge('integration_provider' => 'webhook')
    service.save!
    expect(service.history_sync_payload[:state]).to eq('unsupported')
  end
end
