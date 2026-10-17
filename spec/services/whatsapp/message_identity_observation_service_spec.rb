require 'rails_helper'

RSpec.describe Whatsapp::MessageIdentityObservationService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
  end
  let(:event) do
    { id: 'public-uuid', provider_message_id: 'original-id', type: 'text', from: '5565987654321', timestamp: '1792151940' }
  end
  let(:identity) do
    described_class.new(inbox: channel.inbox, value: { messages: [event] }).perform
    WhatsappMessageIdentity.find_by!(inbox: channel.inbox, external_id: event[:id])
  end

  %i[messages message_echoes].each do |kind|
    it "ignores a no-type #{kind} event without changing the incoming identity" do
      before = identity.attributes
      sparse = event.except(:type).merge(from: channel.phone_number, to: '', provider_message_id: 'contradictory-id')

      described_class.new(inbox: channel.inbox, value: { kind => [sparse] }, outgoing_echo: true).perform

      expect(identity.reload.attributes).to eq(before)
    end

    it "does not create an identity for a no-type #{kind} event" do
      expect do
        described_class.new(inbox: channel.inbox, value: { kind => [event.except(:type)] }).perform
      end.not_to change(WhatsappMessageIdentity, :count)
    end
  end

  it 'retains conflicts for a genuinely typed contradictory echo' do
    identity
    echo = event.merge(from: channel.phone_number, to: event[:from])

    described_class.new(inbox: channel.inbox, value: { message_echoes: [echo] }).perform

    expect(identity.reload.observations.fetch('conflicting_observations')).to include(
      'direction' => %w[incoming outgoing], 'participants.from' => [event[:from], channel.phone_number]
    )
  end

  it 'still records a no-type status without replacing direction or sender' do
    identity
    status = { id: event[:id], status: 'read', recipient_id: event[:from], timestamp: '1792151941' }

    described_class.new(inbox: channel.inbox, value: { statuses: [status] }).perform

    expect(identity.reload.observations).to include(
      'direction' => 'incoming', 'participants' => include('from' => event[:from]), 'statuses' => { 'read' => status[:timestamp] }
    )
  end

  context 'with a Meta API response' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:message) { create(:message, account: channel.account, inbox: channel.inbox, message_type: :outgoing, source_id: 'preserved-public-id') }
    let(:meta_id) { 'wamid.HBgMNTU2NTg3NjU0MzIxFQIAERgWM0VCMEFCQzEyMzc3ODVENkVEMEYyQQA=' }

    it 'records proven identity without claiming delivery or changing the public message ID' do
      described_class.new(inbox: channel.inbox, value: {}).observe_api_response(message: message, external_id: meta_id)
      row = WhatsappMessageIdentity.find_by!(inbox: channel.inbox, external_id: meta_id)

      expect(row.provider_message_id).to eq('3EB0ABC1237785D6ED0F2A')
      expect(row.observations).to include('origin' => 'api_response', 'direction' => 'outgoing', 'message_type' => 'text')
      expect(row.observations['statuses']).to be_nil
      expect(message.reload.source_id).to eq('preserved-public-id')
    end

    it 'does not infer an original ID from an unknown envelope' do
      outgoing = message
      expect do
        described_class.new(inbox: channel.inbox, value: {}).observe_api_response(message: outgoing, external_id: 'wamid.unknown')
      end.not_to change(WhatsappMessageIdentity, :count)
      expect(outgoing.reload.source_id).to eq('preserved-public-id')
    end

    it 'retains contradictory original evidence instead of overwriting it' do
      row = WhatsappMessageIdentity.create!(account: channel.account, inbox: channel.inbox, channel: channel,
                                            provider: 'whatsapp_cloud', external_id: meta_id, provider_message_id: 'existing-original')
      described_class.new(inbox: channel.inbox, value: {}).observe_api_response(message: message, external_id: meta_id)

      expect(row.reload.provider_message_id).to eq('existing-original')
      expect(row.observations.dig('meta_id_adapter', 'status')).to eq('conflicting')
    end
  end
end
