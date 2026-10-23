require 'rails_helper'

RSpec.describe Voip::WebhookHistoryClient do
  let(:service) do
    instance_double(VoipService, id: 2, account_id: 1,
                                 credentials: { 'integration_provider' => 'viperconnect', 'webhook_source_instance_id' => 'pbx-1',
                                                'history_api_url' => 'https://voice.example.com', 'history_api_token' => 'test-secret',
                                                'history_company_id' => 'company-1' })
  end
  let(:scope) { { 'company_id' => 'company-1', 'account_id' => '1', 'service_id' => '2', 'source_instance_id' => 'pbx-1' } }
  let(:event) do
    { 'schema_version' => 1, 'event_id' => 'event-1', 'event_type' => 'call.updated', 'occurred_at' => '2026-10-22T12:00:00Z',
      'source_instance_id' => 'pbx-1', 'call_id' => 'call-1', 'revision' => 1,
      'call' => { 'direction' => 'inbound', 'state' => 'completed', 'started_at' => '2026-10-22T12:00:00Z', 'participants' => [] } }
  end
  let(:payload) do
    { 'version' => 1, 'phase' => 'snapshot', 'items' => [{ 'sequence' => 1, 'webhook_event' => event }],
      'nextCursor' => 'opaque', 'hasMore' => false, 'scope' => scope }
  end
  let(:url) { 'https://voice.example.com/v1/console/history' }
  let(:query) { scope.merge('sync' => 'webhook_events', 'limit' => '100') }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('voice.example.com').and_return(['93.184.216.34'])
    allow(SafeFetch).to receive(:allow_private_network?).and_return(false)
  end

  it 'requests canonical persisted envelopes with explicit company and target using backend bearer' do
    request = stub_request(:get, url).with(query: query, headers: { 'Authorization' => 'Bearer test-secret' })
                                     .to_return(body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
    expect(described_class.new(service).fetch_webhook_events).to eq(payload)
    expect(request).to have_been_requested.once
  end

  it 'rejects cross-company scope, foreign sources and revision mismatches before persistence' do
    [payload.deep_merge('scope' => { 'company_id' => 'other-company' }),
     payload.merge('items' => [{ 'sequence' => 1, 'webhook_event' => event.merge('source_instance_id' => 'foreign') }]),
     payload.merge('items' => [{ 'sequence' => 2, 'webhook_event' => event }])].each do |invalid|
      stub_request(:get, url).with(query: query).to_return(body: invalid.to_json, headers: { 'Content-Type' => 'application/json' })
      expect { described_class.new(service).fetch_webhook_events }.to raise_error(Voip::ServiceHistoryClient::ResponseError)
    end
  end

  { 400 => Voip::ServiceHistoryClient::InvalidCursorError, 409 => Voip::ServiceHistoryClient::ScopeChangedError,
    410 => Voip::ServiceHistoryClient::CursorExpiredError }.each do |code, error|
    it "preserves the typed #{code} cursor error without exposing the response body" do
      stub_request(:get, url).with(query: query.merge('cursor' => 'opaque'))
                             .to_return(status: code, body: 'test-secret')
      expect { described_class.new(service).fetch_webhook_events(cursor: 'opaque') }.to raise_error(error) do |raised|
        expect(raised.message).not_to include('test-secret')
      end
    end
  end
end
