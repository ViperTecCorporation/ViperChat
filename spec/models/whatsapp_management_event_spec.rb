require 'rails_helper'

describe WhatsappManagementEvent do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:attributes) do
    { account: channel.account, channel: channel, inbox: channel.inbox, field: 'security', digest: 'a' * 64,
      state: 'recorded', expires_at: 7.days.from_now }
  end

  it 'belongs to an account, cloud channel and optional inbox' do
    expect(described_class.new(attributes)).to be_valid
    expect(described_class.new(attributes.merge(inbox: nil))).to be_valid
  end

  it 'rejects cross-tenant associations' do
    event = described_class.new(attributes.merge(account: create(:account)))
    expect(event).not_to be_valid
    expect(event.errors[:channel]).to be_present
    expect(event.errors[:inbox]).to be_present
  end

  it 'rejects an inbox from another channel even in the same account' do
    other = create(:channel_whatsapp, account: channel.account, sync_templates: false, validate_provider_config: false)
    event = described_class.new(attributes.merge(inbox: other.inbox))
    expect(event).not_to be_valid
    expect(event.errors[:inbox]).to be_present
  end

  it 'validates states and SHA256 digests' do
    expect(described_class.new(attributes.merge(state: 'imported'))).not_to be_valid
    expect(described_class.new(attributes.merge(digest: 'invalid'))).not_to be_valid
  end

  it 'deduplicates deliveries by account, channel, field and digest' do
    described_class.create!(attributes)
    expect(described_class.new(attributes)).not_to be_valid
    expect(described_class.new(attributes.merge(field: 'account_alerts'))).to be_valid
  end

  it 'has a unique database delivery index, not just a model validation' do
    index = described_class.connection.indexes(:whatsapp_management_events).find(&:unique)
    expect(index.columns).to eq(%w[account_id channel_id field digest])
  end

  it 'rejects payloads beyond the storage budget' do
    event = described_class.new(attributes.merge(payload: { 'large' => 'a' * described_class::MAX_PAYLOAD_BYTES }))
    expect(event).not_to be_valid
    expect(event.errors[:payload]).to be_present
  end

  it 'exposes only safe receipt details even if stored details contain PII' do
    event = described_class.create!(attributes.merge(
                                      details: { 'contacts_count' => 4, 'quality_rating' => 'RED', 'name' => 'Private',
                                                 'status' => 'private@example.test', 'current_limit' => 'Private' },
                                      payload: { 'email' => 'private@example.test' }
                                    ))
    expect(event.summary).to eq(id: event.id, field: 'security', state: 'recorded', received_at: event.created_at,
                                details: { 'contacts_count' => 4, 'quality_rating' => 'RED' })
  end

  it 'exposes a pending import reason without importing or deleting historical messages' do
    event = described_class.create!(attributes.merge(field: 'history', state: 'pending_import', reason: 'user_choice_required'))
    expect(event.summary).to include(state: 'pending_import', reason: 'user_choice_required')
  end

  it 'selects expired administrative receipts without deleting anything' do
    old = described_class.create!(attributes.merge(expires_at: 1.minute.ago))
    fresh = described_class.create!(attributes.merge(digest: 'b' * 64))
    expect(described_class.expired).to include(old)
    expect(described_class.expired).not_to include(fresh)
    expect(described_class.count).to eq(2)
  end

  it 'supports preserving expired receipts while clearing payload and marking pending imports for review' do
    event = described_class.create!(attributes.merge(field: 'history', state: 'pending_import', payload: { 'history' => [] }))
    expect { event.update!(payload: {}, state: 'review', reason: 'payload_expired') }.not_to change(described_class, :count)
    expect(event.reload.digest).to eq('a' * 64)
    expect(event.summary).to include(state: 'review', reason: 'payload_expired')
  end
end
