require 'rails_helper'

RSpec.describe 'VoIP provider webhooks', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:service) do
    VoipService.create!(account: account, name: 'Central', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test',
                        credentials: { integration_provider: 'webhook', webhook_source_instance_id: 'pbx-1' })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/voip/services/#{service.id}/events" }
  let(:headers) { { 'api_access_token' => admin.access_token.token } }
  let(:payload) do
    { schema_version: 1, event_id: 'event-1', event_type: 'call.ringing', occurred_at: '2026-10-22T12:00:00Z',
      source_instance_id: 'pbx-1', call_id: 'call-1', revision: 1,
      call: { direction: 'inbound', state: 'ringing', started_at: '2026-10-22T12:00:00Z', participants: [] } }
  end

  it 'persists before acknowledging and deduplicates semantic JSON retries' do
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    expect(VoipProviderEvent.count).to eq(1)
    post url, params: payload.to_a.reverse.to_h, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['status']).to eq('duplicate')
    expect(VoipProviderEvent.count).to eq(1)
  end

  it 'accepts complete artifact snapshots with multiline AI and rejects unsafe extra fields and limits' do
    payload[:event_type] = 'call.artifacts.updated'
    payload[:call][:artifacts] = { recording: { status: 'available', record_id: 'record-1', mime_type: 'audio/wav', size_bytes: 1024,
                                                sha256: 'a' * 64 },
                                   ai: { status: 'completed', summary: "Resumo\nseguro", transcript: "Olá\tTeste" },
                                   note_target: { business_phone: '5566996222471', remote_phone: '5566999999999' } }
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    [[:ai, :summary, 'x' * 16_001], [:recording, :size_bytes, 51.megabytes], [:recording, :url, 'https://unsafe.example'],
     [:note_target, :inbox_id, 123], [:ai, :transcript, "bad\u0000text"]].each do |section, key, value|
      invalid = payload.deep_dup
      invalid[:call][:artifacts][section][key] = value
      post url, params: invalid, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(VoipProviderEvent.count).to eq(1)
  end

  it 'rejects changes to stored recording identity while accepting later matching integrity metadata' do
    external = VoipExternalCall.create!(voip_service: service, source_instance_id: 'pbx-1', provider_call_id: 'call-1')
    recording = { 'status' => 'available', 'record_id' => 'record-1' }
    artifact = external.create_voip_call_artifact!(snapshot: { 'recording' => recording }, recording_digest: Digest::SHA256.hexdigest('audio'))
    artifact.recording.attach(io: StringIO.new('audio'), filename: 'recording.wav', content_type: 'audio/wav')
    original_blob = artifact.recording.blob.id
    payload[:event_type] = 'call.artifacts.updated'
    payload[:call][:artifacts] = { recording: recording }
    [{ 'record_id' => 'another' }, { 'sha256' => 'b' * 64 }, { 'size_bytes' => 6 }].each do |change|
      invalid = payload.deep_dup
      invalid[:call][:artifacts][:recording] = recording.merge(change)
      post url, params: invalid, headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
    end
    payload[:call][:artifacts][:recording] = recording.merge('sha256' => artifact.recording_digest, 'size_bytes' => 5)
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    expect(artifact.reload.recording.blob.id).to eq(original_blob)
  end

  it 'rejects divergent event id and revision reuse' do
    post url, params: payload, headers: headers, as: :json
    post url, params: payload.merge(event_type: 'call.created'), headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    post url, params: payload.merge(event_id: 'different-event'), headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(VoipProviderEvent.count).to eq(1)
  end

  it 'rejects cookie login, bearer, invalid tokens, agents and bots' do
    [admin.create_new_auth_token, { Authorization: "Bearer #{admin.access_token.token}" }, { api_access_token: 'invalid' },
     { api_access_token: agent.access_token.token }, { api_access_token: create(:agent_bot).access_token.token }].each do |credentials|
      post url, params: payload, headers: credentials, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
    expect(VoipProviderEvent.count).to eq(0)
  end

  it 'rejects foreign administrators, producer mismatch and disabled services' do
    foreign = create(:user, role: :administrator)
    post url, params: payload, headers: { api_access_token: foreign.access_token.token }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post url, params: payload.merge(source_instance_id: 'other'), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    service.update!(enabled: false)
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'scopes the service to the authenticated account and never trusts body account ids' do
    foreign_service = VoipService.create!(account: create(:account), name: 'Foreign',
                                          wss_url: 'wss://sip.example.test', sip_domain: 'sip.example.test')
    post url.sub("/#{service.id}/events", "/#{foreign_service.id}/events"), params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post url, params: payload.merge(account_id: foreign_service.account_id), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    expect(VoipProviderEvent.sole.voip_service.account_id).to eq(account.id)
  end

  it 'rejects oversized bodies and filters caller snapshots from request parameters' do
    post url, params: payload.merge(padding: 'x' * 256.kilobytes), headers: headers, as: :json
    expect(response).to have_http_status(:payload_too_large)
    expect(VoipProviderEvent.count).to eq(0)
    post url, params: payload, headers: headers, as: :json
    expect(request.filtered_parameters['call']).to eq('[FILTERED]')
  end

  it 'keeps its durable inbox when enqueue fails and retries through recovery' do
    allow(Voip::ProcessProviderEventJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    expect(VoipProviderEvent.pending.count).to eq(1)
    allow(Voip::ProcessProviderEventJob).to receive(:perform_later)
    Voip::RecoverProviderEventsJob.perform_now
    expect(Voip::ProcessProviderEventJob).to have_received(:perform_later).with(VoipProviderEvent.first.id).twice
  end

  it 'rejects unsupported schema, unsafe phone identity and excessive participants' do
    [payload.merge(schema_version: 2), payload.merge(schema_version: 1.0),
     payload.merge(call: payload[:call].merge(from: { kind: 'phone', value: '123@lid' })),
     payload.merge(call: payload[:call].merge(participants: Array.new(101) { { id: 'leg', state: 'ringing' } }))].each do |invalid|
      post url, params: invalid, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(VoipProviderEvent.count).to eq(0)
  end

  it 'rejects all undeclared envelope and nested fields rather than persisting credentials, URLs or audio' do
    variants = [payload.merge(token: 'synthetic'), payload.merge(url: 'https://example.test'), payload.merge(audio: 'synthetic'),
                payload.merge(call: payload[:call].merge(password: 'synthetic')),
                payload.merge(call: payload[:call].merge(from: { kind: 'phone', value: '5566999999999', token: 'synthetic' })),
                payload.merge(call: payload[:call].merge(participants: [{ id: 'leg', state: 'ringing', audio: 'synthetic' }])),
                payload.merge(call: payload[:call].merge(recording: { status: 'available', record_id: 'record', url: 'https://example.test' }))]
    variants.each do |invalid|
      post url, params: invalid, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(VoipProviderEvent.count).to eq(0)
  end

  it 'accepts UTC Z and +00:00 but rejects offset timestamps' do
    post url, params: payload.merge(occurred_at: '2026-10-22T12:00:00+00:00'), headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    post url, params: payload.merge(event_id: 'offset', revision: 2, occurred_at: '2026-10-22T08:00:00-04:00'), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(VoipProviderEvent.count).to eq(1)
  end
end
