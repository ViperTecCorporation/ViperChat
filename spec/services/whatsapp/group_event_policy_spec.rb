require 'rails_helper'

RSpec.describe Whatsapp::GroupEventPolicy do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:policy) { described_class.new(inbox: channel.inbox) }

  # Local settings must not make real provider validation requests.
  before { channel.update_columns(provider_config: channel.provider_config.merge('ignore_group_messages' => true)) } # rubocop:disable Rails/SkipsModelValidations

  it 'ignores groups but not normal messages, without treating a BSUID as a group' do
    expect(policy.ignored?({ messages: [{ group_id: 'opaque-group', from: 'BR.123' }] })).to be(true)
    expect(policy.ignored?({ messages: [{ from: 'BR.123' }] })).to be(false)
    expect(policy.ignored?({}, field: 'group_participants_update')).to be(true)
  end

  it 'recognizes group contacts, echoes and statuses before persistence' do
    expect(policy.ignored?({ contacts: [{ group_id: '123@g.us' }], messages: [{ from: '5566996269251' }] })).to be(true)
    expect(policy.ignored?({ message_echoes: [{ to: '123@g.us' }] })).to be(true)
    expect(policy.ignored?({ statuses: [{ recipient_type: 'group', recipient_id: 'opaque-group' }] })).to be(true)
  end

  it 'retains ordinary statuses in a mixed batch without modifying the source payload' do
    value = { statuses: [{ recipient_type: 'group', id: 'group' }, { recipient_id: '5566996269251', id: 'direct' }] }
    expect(policy.ignored?(value)).to be(false)
    expect(policy.filter(value)[:statuses].pluck(:id)).to eq(['direct'])
    expect(value[:statuses].size).to eq(2)
  end

  it 'preserves missing/disabled configuration and leaves the UnoAPI provider filter unchanged' do
    channel.update_columns(provider_config: {}) # rubocop:disable Rails/SkipsModelValidations
    expect(policy.ignored?({}, field: 'group_settings_update')).to be(false)
    channel.update_columns(provider: 'unoapi', provider_config: { 'ignore_group_messages' => true }) # rubocop:disable Rails/SkipsModelValidations
    expect(policy.ignored?({}, field: 'group_settings_update')).to be(false)
  end

  it 'blocks direct ingestion before observing identities, creating contacts or downloading files' do
    value = { messages: [{ id: 'ignored-file', group_id: '123@g.us', type: 'image', image: { id: 'media' } }] }
    params = { entry: [{ changes: [{ value: value }] }] }.with_indifferent_access
    expect(Whatsapp::MessageIdentityObservationService).not_to receive(:new)
    expect do
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
    end.not_to change(Contact, :count)
    expect(channel.inbox.messages).to be_empty
  end

  it 'ignores group administration before creating receipts or updating group data' do
    body = { phone_number: channel.phone_number, entry: [{ changes: [{ field: 'group_settings_update', value: { group_id: '123' } }] }] }
    expect(Whatsapp::ManagementWebhookService).not_to receive(:new)
    Webhooks::WhatsappEventsJob.perform_now(body)
    expect(WhatsappManagementEvent.count).to eq(0)
  end

  it 'does not interpret malformed or future administrative values as group payloads' do
    [nil, [], 'future-format'].each do |value|
      expect(policy.ignored?(value, field: 'account_alerts')).to be(false)
      expect(policy.filter(value)).to eq(value)
    end
  end
end
