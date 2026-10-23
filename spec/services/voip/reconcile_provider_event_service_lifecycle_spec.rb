require 'rails_helper'

RSpec.describe Voip::ReconcileProviderEventService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:service) do
    VoipService.create!(account: account, name: 'Synthetic PBX', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test',
                        credentials: { integration_provider: 'webhook', webhook_source_instance_id: 'pbx-synthetic' })
  end
  let!(:binding) do
    VoipAgentExtension.create!(account_user: agent.account_users.find_by!(account: account), voip_service: service,
                               extension: '1001', auth_username: '1001', credentials: { password: 'synthetic' }, active: true)
  end
  let(:envelope) do
    { 'schema_version' => 1, 'event_id' => 'synthetic-1', 'event_type' => 'call.ringing', 'source_instance_id' => 'pbx-synthetic',
      'call_id' => 'synthetic-call', 'revision' => 1, 'occurred_at' => '2026-10-22T12:00:00Z',
      'call' => { 'direction' => 'inbound', 'state' => 'ringing', 'started_at' => '2026-10-22T12:00:00Z',
                  'from' => { 'kind' => 'phone', 'value' => '15555552001' }, 'to' => { 'kind' => 'extension', 'value' => '1001' },
                  'participants' => [{ 'id' => 'leg-1', 'sip_call_id' => 'synthetic-sip-1', 'extension' => '1001', 'state' => 'ringing' }] } }
  end

  terminal_states = %w[completed missed failed cancelled].freeze
  %w[inbound outbound].each do |direction|
    terminal_states.each do |terminal|
      it "consolidates #{direction} / #{terminal} after delayed and duplicate events without a browser" do
        first = envelope.deep_dup
        first['call']['direction'] = direction
        first['call']['from'], first['call']['to'] = first['call']['to'], first['call']['from'] if direction == 'outbound'
        event, = Voip::ReceiveProviderEventService.new(service: service, payload: first).perform
        Voip::ProcessProviderEventJob.perform_now(event.id)
        call = VoipCall.sole
        expect(call.direction).to eq(direction == 'inbound' ? 'incoming' : 'outgoing')
        original_id = call.id

        last = first.deep_dup
        last.merge!('event_id' => 'synthetic-3', 'revision' => 3, 'event_type' => 'call.ended', 'occurred_at' => '2026-10-22T12:02:00Z')
        last['call'].merge!('state' => terminal, 'ended_at' => '2026-10-22T12:02:00Z', 'end_reason' => terminal)
        last['call']['participants'].first.merge!('state' => terminal, 'ended_at' => '2026-10-22T12:02:00Z')
        if terminal == 'completed'
          last['call']['answered_at'] = '2026-10-22T12:01:00Z'
          last['call']['participants'].first['answered_at'] = '2026-10-22T12:01:00Z'
        end
        event, = Voip::ReceiveProviderEventService.new(service: service, payload: last).perform
        Voip::ProcessProviderEventJob.perform_now(event.id)
        duplicate, duplicated = Voip::ReceiveProviderEventService.new(service: service, payload: last).perform
        expect(duplicated).to be(true)
        Voip::ProcessProviderEventJob.perform_now(duplicate.id)

        delayed = first.merge('event_id' => 'synthetic-2', 'revision' => 2)
        event, = Voip::ReceiveProviderEventService.new(service: service, payload: delayed).perform
        Voip::ProcessProviderEventJob.perform_now(event.id)
        expect([VoipCall.count, Message.count]).to eq([1, 0])
        expect(call.reload.id).to eq(original_id)
        expect(call.state).to eq(terminal == 'completed' ? 'ended' : terminal)
        expect(call.ended_at).to eq(Time.iso8601('2026-10-22T12:02:00Z'))
        expect(VoipProviderEvent.pending).to be_empty
      end
    end
  end

  it 'corrects a legacy missed summary only from exact answered participant evidence without changing the source event or leg ids' do
    payload = envelope.deep_dup
    payload['event_type'] = 'call.ended'
    payload['call'].merge!('state' => 'missed', 'ended_at' => '2026-10-22T12:02:00Z')
    payload['call']['participants'].first.merge!('state' => 'completed', 'answered_at' => '2026-10-22T12:01:00Z',
                                                 'ended_at' => '2026-10-22T12:02:00Z')
    payload['call']['participants'] << { 'id' => 'udp-leg', 'sip_call_id' => 'udp-dialog', 'extension' => '1001',
                                         'state' => 'answered_elsewhere', 'ended_at' => '2026-10-22T12:01:00Z' }
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    Voip::ProcessProviderEventJob.perform_now(event.id)
    external = VoipExternalCall.find_by!(voip_service: service, provider_call_id: payload['call_id'])
    expect(external.snapshot).to include('state' => 'completed', 'answered_at' => '2026-10-22T12:01:00Z')
    expect(event.reload.payload).to eq(payload)
    expect(external.voip_calls.count).to eq(2)
    expect(external.voip_calls.consolidated_history.sole).to have_attributes(state: 'ended', sip_call_id: 'synthetic-sip-1')
  end

  it 'keeps transfer legs, answered-elsewhere and internal caller/callee identities distinct' do
    other_agent = create(:user, account: account, role: :agent)
    other_binding = VoipAgentExtension.create!(account_user: other_agent.account_users.find_by!(account: account), voip_service: service,
                                               extension: '1002', auth_username: '1002', credentials: { password: 'synthetic' }, active: true)
    payload = envelope.deep_dup
    payload['call']['direction'] = 'internal'
    payload['call']['from'] = { 'kind' => 'extension', 'value' => '1001' }
    payload['call']['to'] = { 'kind' => 'extension', 'value' => '1002' }
    payload['call']['participants'] << { 'id' => 'leg-2', 'sip_call_id' => 'synthetic-sip-2', 'extension' => '1002', 'state' => 'ringing' }
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    Voip::ProcessProviderEventJob.perform_now(event.id)
    originals = VoipCall.order(:id).pluck(:id)
    expect(binding.voip_calls.sole.direction).to eq('outgoing')
    expect(other_binding.voip_calls.sole.direction).to eq('incoming')
    payload.merge!('event_id' => 'synthetic-transfer', 'event_type' => 'call.transferred', 'revision' => 2)
    payload['call']['state'] = 'active'
    payload['call']['participants'][0].merge!('state' => 'answered_elsewhere', 'ended_at' => '2026-10-22T12:01:00Z')
    payload['call']['participants'][1].merge!('state' => 'active', 'answered_at' => '2026-10-22T12:01:00Z')
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    Voip::ProcessProviderEventJob.perform_now(event.id)
    expect(binding.voip_calls.sole.state).to eq('answered_elsewhere')
    expect(other_binding.voip_calls.sole.state).to eq('active')
    payload.merge!('event_id' => 'synthetic-bye', 'event_type' => 'call.ended', 'revision' => 3)
    payload['call'].merge!('state' => 'completed', 'ended_at' => '2026-10-22T12:03:00Z')
    payload['call']['participants'][1].merge!('state' => 'completed', 'ended_at' => '2026-10-22T12:03:00Z')
    event, = Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    Voip::ProcessProviderEventJob.perform_now(event.id)
    expect(VoipCall.order(:id).pluck(:id)).to eq(originals)
    expect([binding.voip_calls.sole.state, other_binding.voip_calls.sole.state]).to eq(%w[answered_elsewhere ended])
    expect(VoipExternalCall.count).to eq(1)
  end
end
