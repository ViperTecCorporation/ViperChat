require 'rails_helper'

RSpec.describe Voip::ReconcileProviderEventService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:service) do
    VoipService.create!(account: account, name: 'Central', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test',
                        credentials: { integration_provider: 'webhook', webhook_source_instance_id: 'pbx-1' })
  end
  let!(:binding) do
    VoipAgentExtension.create!(account_user: agent.account_users.find_by!(account: account), voip_service: service,
                               extension: '1001', auth_username: '1001', credentials: { password: 'synthetic-secret' }, active: true)
  end
  let(:snapshot) do
    { 'direction' => 'inbound', 'state' => 'ringing', 'started_at' => '2026-10-22T12:00:00Z',
      'from' => { 'kind' => 'phone', 'value' => '5566999999999', 'name' => 'Caller' },
      'to' => { 'kind' => 'extension', 'value' => '1001' },
      'participants' => [{ 'id' => 'leg-1', 'extension' => '1001', 'sip_call_id' => 'sip-1', 'state' => 'ringing' }] }
  end
  let(:payload) do
    { 'schema_version' => 1, 'event_id' => 'event-1', 'event_type' => 'call.ringing', 'occurred_at' => '2026-10-22T12:00:00Z',
      'source_instance_id' => 'pbx-1', 'call_id' => 'call-1', 'revision' => 1, 'call' => snapshot }
  end

  it 'links only the exact SIP dialog and binding, preserving the original call and observations' do
    call = binding.voip_calls.create!(account: account, client_call_id: 'client-original', sip_call_id: 'sip-1', direction: 'incoming',
                                      remote_address: '5566999999999', started_at: Time.current, last_observed_at: Time.current)
    observation = call.voip_call_observations.create!(event_id: 'original-event', sequence: 1, state: 'ringing')
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    described_class.new(event: event).perform
    expect(VoipCall.count).to eq(1)
    expect(call.reload.client_call_id).to eq('client-original')
    expect(call.voip_external_call).to be_present
    expect(observation.reload.voip_call_id).to eq(call.id)
    expect(event.reload.processed_at).to be_present
  end

  it 'keeps artifact work durable after event processing when the artifact job queue is unavailable' do
    snapshot['artifacts'] = { 'ai' => { 'status' => 'completed', 'summary' => 'Resumo' } }
    payload['event_type'] = 'call.artifacts.updated'
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    allow(Voip::PublishCallArtifactJob).to receive(:perform_later).and_raise(IOError, 'synthetic queue failure')
    described_class.new(event: event).perform
    expect(event.reload.processed_at).to be_present
    artifact = VoipCallArtifact.sole
    expect(artifact.snapshot).to eq(snapshot['artifacts'])
    expect(VoipCallArtifact.due).to include(artifact)
    allow(Voip::PublishCallArtifactJob).to receive(:perform_later)
    Voip::RecoverProviderEventsJob.perform_now
    expect(Voip::PublishCallArtifactJob).to have_received(:perform_later).with(artifact.id).twice
  end

  it 'records calls while the browser is closed and joins later client creation by exact SIP id' do
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    described_class.new(event: event).perform
    projected = VoipCall.sole
    expect(projected.origin).to eq('provider_authoritative')
    call = Voip::CreateCallService.new(binding: binding, attributes: { client_call_id: 'client-later', sip_call_id: 'sip-1',
                                                                       direction: 'incoming', remote_address: '5566999999999' }).perform
    expect(call.id).to eq(projected.id)
    expect(VoipCall.count).to eq(1)
  end

  it 'does not invent agent bindings or correlate by telephone when SIP evidence is missing' do
    snapshot['participants'].first.delete('sip_call_id')
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    described_class.new(event: event).perform
    expect(VoipExternalCall.count).to eq(1)
    expect(VoipCall.count).to eq(0)
  end

  it 'preserves the occurrence time of old live events so replay does not make stale calls look live' do
    payload['occurred_at'] = 10.minutes.ago.utc.iso8601
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    described_class.new(event: event).perform
    expect(VoipCall.sole.last_observed_at).to eq(Time.iso8601(payload.fetch('occurred_at')))
    expect(VoipCall.sole.public_payload[:state]).to eq('awaiting_confirmation')
  end

  it 'clamps future occurrence times to the current time rather than extending live state indefinitely' do
    payload['occurred_at'] = 2.days.from_now.utc.iso8601
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    before_projection = Time.current
    described_class.new(event: event).perform
    expect(VoipCall.sole.last_observed_at).to be_between(before_projection, Time.current)
    expect(VoipCall.sole.public_payload[:state]).to eq('ringing')
  end

  it 'ignores old revisions and prevents terminal calls reopening on a newer recording update' do
    final = snapshot.deep_merge('state' => 'completed', 'ended_at' => '2026-10-22T12:01:00Z')
    final['participants'].first['state'] = 'completed'
    event, = Voip::ReceiveProviderEventService.new(service: service,
                                                   payload: payload.merge('event_id' => 'event-2', 'revision' => 2, 'call' => final)).perform
    described_class.new(event: event).perform
    old, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    described_class.new(event: old).perform
    expect(VoipCall.sole.state).to eq('ended')
    late, = Voip::ReceiveProviderEventService.new(service: service,
                                                  payload: payload.merge('event_id' => 'event-3', 'revision' => 3)).perform
    described_class.new(event: late).perform
    expect(VoipCall.sole.state).to eq('ended')
    expect(VoipExternalCall.sole.revision).to eq(3)
    expect(VoipProviderEvent.pending.count).to eq(0)
  end
end
