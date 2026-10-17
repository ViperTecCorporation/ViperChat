require 'rails_helper'

# Real DB claims using independent Message instances, never provider HTTP.
# The main agent owns DB execution; do not run concurrently with its suite.
RSpec.describe Whatsapp::UnifiedDeliveryAttemptService do
  let(:account) { create(:account) }
  let(:metadata) do
    {
      'link_id' => 123, 'activation_cutoff' => '2026-10-16T12:00:00.000000Z',
      'requested_provider' => 'whatsapp_cloud', 'provider' => 'unoapi',
      'inbox_id' => 456, 'capability' => 'pix', 'reason' => 'capability_routing'
    }
  end
  let(:message) do
    create(:message, account: account, message_type: :outgoing, status: :progress,
                     content: 'Synthetic delivery', content_attributes: { 'whatsapp_transport' => metadata, 'synthetic_marker' => 'keep' })
  end

  it 'persists the claim before yielding and blocks a second job using a separately loaded instance' do
    first_job = described_class.new(message: message)
    second_job = described_class.new(message: Message.find(message.id))
    external_calls = 0

    first_job.perform do
      external_calls += 1
      persisted = Message.find(message.id).content_attributes.fetch('whatsapp_transport')
      expect(persisted).to include(metadata.merge('delivery_state' => 'attempting'))
      expect(persisted['delivery_attempt_id']).to match(/\A[0-9a-f-]{36}\z/)
      expect(Time.iso8601(persisted.fetch('delivery_attempted_at'))).to be_within(5.seconds).of(Time.current)
      expect { second_job.perform { external_calls += 1 } }.to raise_error do |error|
        expect(error.class.name).to eq('Whatsapp::UnifiedDeliveryAttemptService::UncertainDelivery')
      end
    end

    expect(external_calls).to eq(1)
    expect(message.reload.content_attributes.dig('whatsapp_transport', 'delivery_state')).to eq('uncertain')
    expect(message.external_error).to eq(described_class::REVIEW_ERROR)
    expect { second_job.perform { external_calls += 1 } }.to raise_error do |error|
      expect(error.class.name).to eq('Whatsapp::UnifiedDeliveryAttemptService::UncertainDelivery')
    end
    expect(external_calls).to eq(1)
  end

  [Net::ReadTimeout, RuntimeError].each do |error_class|
    it "preserves the original #{error_class.name} and never resends an uncertain attempt" do
      original_error = error_class.new('synthetic private payload must not be persisted')
      external_calls = 0
      expect do
        described_class.new(message: message).perform do
          external_calls += 1
          raise original_error
        end
      end.to raise_error { |error| expect(error).to equal(original_error) }

      persisted = message.reload.content_attributes.deep_dup
      expect(persisted.dig('whatsapp_transport', 'delivery_state')).to eq('uncertain')
      expect(message.external_error).to eq(described_class::REVIEW_ERROR)
      expect(persisted.to_json).not_to include(original_error.message)
      expect do
        described_class.new(message: Message.find(message.id)).perform { external_calls += 1 }
      end.to raise_error do |error|
        expect(error.class.name).to eq('Whatsapp::UnifiedDeliveryAttemptService::UncertainDelivery')
      end
      expect(message.reload.content_attributes).to eq(persisted)
      expect(external_calls).to eq(1)
    end
  end

  it 'acknowledges a persisted source ID, preserves metadata and makes subsequent jobs idempotent' do
    external_calls = 0
    result = described_class.new(message: message).perform do
      external_calls += 1
      # A different instance represents the caller persisting the HTTP response.
      Message.find(message.id).update!(source_id: 'synthetic-provider-public-id')
      :provider_result
    end

    expect(result).to eq(:provider_result)
    attributes = message.reload.content_attributes.deep_dup
    expect(attributes.fetch('whatsapp_transport')).to include(metadata.merge('delivery_state' => 'acknowledged'))
    expect(attributes['synthetic_marker']).to eq('keep')
    expect(message.external_error).to be_blank
    expect(described_class.new(message: Message.find(message.id)).perform { external_calls += 1 }).to be_nil
    expect(message.reload.content_attributes).to eq(attributes)
    expect(message.source_id).to eq('synthetic-provider-public-id')
    expect(external_calls).to eq(1)
  end

  it 'skips an already persisted source ID even when no delivery claim exists' do
    message.update!(source_id: 'synthetic-existing-source')
    before_attributes = message.reload.content_attributes.deep_dup
    yielded = false

    described_class.new(message: message).perform { yielded = true }

    expect(yielded).to be(false)
    expect(message.reload.content_attributes).to eq(before_attributes)
  end

  it 'does not reset a claimed attempt when transport activation metadata changes' do
    described_class.new(message: message).perform { nil }
    attributes = message.reload.content_attributes.deep_dup
    attempt_id = attributes.dig('whatsapp_transport', 'delivery_attempt_id')
    attributes['whatsapp_transport']['activation_cutoff'] = '2026-10-16T13:00:00.000000Z'
    message.update!(content_attributes: attributes)
    yielded = false

    expect { described_class.new(message: Message.find(message.id)).perform { yielded = true } }.to raise_error do |error|
      expect(error.class.name).to eq('Whatsapp::UnifiedDeliveryAttemptService::UncertainDelivery')
    end

    expect(yielded).to be(false)
    expect(message.reload.content_attributes.dig('whatsapp_transport', 'delivery_attempt_id')).to eq(attempt_id)
    expect(message.content_attributes.fetch('whatsapp_transport')).to include(metadata.except('activation_cutoff'))
  end

  it 'passes legacy messages through without claiming or changing their metadata' do
    message.update!(content_attributes: { 'synthetic_marker' => 'legacy' })
    before_attributes = message.reload.content_attributes.deep_dup
    calls = 0

    2.times do
      expect(described_class.new(message: Message.find(message.id)).perform { calls += 1; :legacy_result }).to eq(:legacy_result)
    end

    expect(calls).to eq(2)
    expect(message.reload.content_attributes).to eq(before_attributes)
    expect(message.external_error).to be_blank
  end
end
