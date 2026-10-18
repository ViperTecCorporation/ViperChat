require 'rails_helper'

RSpec.describe Whatsapp::GroupMessageIngestionService do
  let(:account) { create(:account) }
  let(:primary) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5565998765432',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:secondary) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556598765432',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:link) do
    WhatsappInboxLink.create!(account: account, primary_inbox: primary, secondary_inbox: secondary,
                              default_provider: 'unoapi', enabled: true, activated_at: 1.hour.ago)
  end
  let(:value) { { messages: [{ id: 'secondary-public', group_id: '123@g.us', type: 'image' }] }.with_indifferent_access }
  let(:observations) do
    { 'direction' => 'incoming', 'message_type' => 'image', 'business_number' => primary.channel.phone_number,
      'participants' => { 'group_id' => '123@g.us', 'from' => '5566996269251' } }
  end
  let!(:identity) do
    WhatsappMessageIdentity.create!(account: account, inbox: secondary, channel: secondary.channel, provider: 'whatsapp_cloud',
                                    external_id: 'secondary-public', provider_message_id: 'original-group', observations: observations)
  end
  let(:candidate) do
    WhatsappMessageIdentity.create!(account: account, inbox: primary, channel: primary.channel, provider: 'unoapi',
                                    external_id: 'primary-public', provider_message_id: 'original-group', observations: observations)
  end
  let(:conversation) { create(:conversation, inbox: primary, account: account, group: true, group_source_id: '123@g.us') }
  let(:message) { create(:message, :incoming, account: account, inbox: primary, conversation: conversation, source_id: 'primary-public') }
  let(:service) { described_class.new(inbox: secondary, value: value) }

  before { link }

  it 'waits durably without creating a contact or downloading when the primary counterpart is unknown' do
    expect { service.perform { raise 'must not ingest/download' } }.to change(WhatsappUnifiedEvent, :count).by(1)
    expect(WhatsappUnifiedEvent.last.reason).to eq('identity_pending')
    expect { service.perform { raise 'must not ingest/download' } }.not_to change(WhatsappUnifiedEvent, :count)
    expect(account.contacts).to be_empty
  end

  it 'adopts only an exact primary group, sender, direction and original ID while preserving both public IDs' do
    candidate.message_links.create_or_find_by!(message: message)
    expect(service.perform { raise 'must not ingest/download' }).to eq(message)
    expect(WhatsappUnifiedMessageAlias.find_by!(whatsapp_message_identity: identity).message).to eq(message)
    expect(message.reload.source_id).to eq('primary-public')
    expect(identity.reload.external_id).to eq('secondary-public')
    expect(account.messages.where(message_type: :incoming).count).to eq(1)
  end

  %w[group_id from].each do |key|
    it "does not correlate reused original IDs with a different #{key}" do
      candidate.update!(observations: observations.deep_merge('participants' => { key => 'other' }))
      candidate.message_links.create_or_find_by!(message: message)
      expect(service.perform { raise 'must not ingest/download' }).to be_nil
      expect(WhatsappUnifiedMessageAlias.count).to eq(0)
      expect(WhatsappUnifiedEvent.last.state).to eq('pending')
    end
  end

  it 'does not infer an original group ID from unknown Meta WAMIDs' do
    identity.update!(provider_message_id: nil)
    candidate.message_links.create_or_find_by!(message: message)
    expect(service.perform { raise 'must not ingest/download' }).to be_nil
    expect(WhatsappUnifiedMessageAlias.count).to eq(0)
  end

  it 'updates an exact group status through its proven alias, never another group' do
    candidate.message_links.create_or_find_by!(message: message)
    service.perform { raise 'must not ingest/download' }
    status = { id: identity.external_id, recipient_type: 'group', recipient_id: '123@g.us', status: 'read' }
    params = { entry: [{ changes: [{ value: { statuses: [status] } }] }] }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: secondary, params: params).perform
    expect(message.reload.status).to eq('read')
    message.update!(status: :sent)
    params[:entry][0][:changes][0][:value][:statuses][0][:recipient_id] = 'different-group@g.us'
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: secondary, params: params).perform
    expect(message.reload.status).to eq('sent')
  end

  context 'when Meta is the primary inbox' do
    let(:link) do
      WhatsappInboxLink.create!(account: account, primary_inbox: secondary, secondary_inbox: primary,
                                default_provider: 'whatsapp_cloud', enabled: true, activated_at: 1.hour.ago)
    end

    it 'never blocks or downloads a replacement for an existing Uno group flow' do
      marker = Object.new
      expect(described_class.new(inbox: primary, value: value).perform { marker }).to equal(marker)
      expect(WhatsappUnifiedEvent.count).to eq(0)
    end

    it 'can adopt a proven Uno message even in the secondary inbox without moving IDs or media' do
      candidate.message_links.create_or_find_by!(message: message)
      expect(service.perform { raise 'must not ingest/download' }).to eq(message)
      expect(message.reload.inbox_id).to eq(primary.id)
      expect(WhatsappUnifiedMessageAlias.find_by!(whatsapp_message_identity: identity).message).to eq(message)
    end
  end
end
