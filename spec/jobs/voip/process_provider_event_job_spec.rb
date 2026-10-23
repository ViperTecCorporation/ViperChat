require 'rails_helper'

RSpec.describe Voip::ProcessProviderEventJob do
  let(:account) { create(:account) }
  let(:service) do
    VoipService.create!(account: account, name: 'Central', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test',
                        credentials: { integration_provider: 'webhook', webhook_source_instance_id: 'pbx-1' })
  end
  let(:event) do
    VoipProviderEvent.create!(voip_service: service, source_instance_id: 'pbx-1', event_id: 'event-1', provider_call_id: 'call-1',
                              revision: 1, content_digest: 'digest', payload: { 'synthetic' => true })
  end

  it 'records sanitized failures with bounded retries and stops after eight attempts' do
    reconciler = instance_double(Voip::ReconcileProviderEventService)
    allow(Voip::ReconcileProviderEventService).to receive(:new).with(event: event).and_return(reconciler)
    allow(reconciler).to receive(:perform).and_raise(StandardError, 'private credentials')
    described_class.perform_now(event.id)
    expect(event.reload).to have_attributes(attempts: 1, last_error_code: 'processing_failed')
    expect(event.next_attempt_at).to be > Time.current
    described_class.perform_now(event.id)
    expect(event.reload.attempts).to eq(1)
    event.update!(attempts: 7, next_attempt_at: nil)
    described_class.perform_now(event.id)
    expect(event.reload).to have_attributes(attempts: 8, next_attempt_at: nil)
    expect(VoipProviderEvent.due).not_to include(event)
    described_class.perform_now(event.id)
    expect(event.reload.attempts).to eq(8)
  end

  it 'never processes disabled, reconfigured or already completed events' do
    expect(Voip::ReconcileProviderEventService).not_to receive(:new)
    service.update!(enabled: false)
    described_class.perform_now(event.id)
    service.update!(enabled: true)
    event.update!(source_instance_id: 'old-source')
    described_class.perform_now(event.id)
    event.update!(source_instance_id: 'pbx-1', processed_at: Time.current)
    described_class.perform_now(event.id)
  end
end
