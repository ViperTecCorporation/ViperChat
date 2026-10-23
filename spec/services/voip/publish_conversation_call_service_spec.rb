require 'rails_helper'

RSpec.describe Voip::PublishConversationCallService do
  let(:account) { create(:account) }
  let(:service) { VoipService.create!(account: account, name: 'PBX', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test') }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+5566996222471', provider: 'unoapi',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5566999999999') }
  let!(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, status: :resolved) }
  let(:snapshot) do
    { 'direction' => 'inbound', 'state' => 'ringing', 'started_at' => Time.current.iso8601, 'business_phone' => '5566996222471',
      'from' => { 'kind' => 'phone', 'value' => '5566999999999' }, 'participants' => [] }
  end
  let(:external) { VoipExternalCall.create!(voip_service: service, source_instance_id: 'test', provider_call_id: 'call-1', snapshot: snapshot) }

  it 'updates one private voice card through the lifecycle, without reopening or sending a WhatsApp message by default' do
    described_class.new(external: external).perform
    message = external.reload.call_message
    expect(message).to have_attributes(content_type: 'voice_call', private: true)
    expect(conversation.reload).to be_resolved
    expect(enqueued_jobs.pluck(:job)).not_to include(SendReplyJob)
    %w[active completed].each do |state|
      external.update!(snapshot: snapshot.merge('state' => state))
      expect { described_class.new(external: external).perform }.not_to change(Message, :count)
      expect(external.reload.call_message_id).to eq(message.id)
      expect(message.reload.content_attributes.dig('data', 'state')).to eq(state)
    end
    expect(conversation.reload).to be_resolved
  end

  it 'reopens a single-conversation inbox only on the first incoming call event' do
    service.credentials = { 'reopen_on_incoming' => true }
    service.save!
    channel.inbox.update!(lock_to_single_conversation: true)
    described_class.new(external: external).perform
    expect(external.reload.conversation_id).to eq(conversation.id)
    expect(conversation.reload).to be_open
    conversation.resolved!
    described_class.new(external: external).perform
    expect(conversation.reload).to be_resolved
  end

  it 'preserves analysis through lifecycle updates and promotes an earlier artifact note without changing its id' do
    note = create(:message, conversation: conversation, private: true, content: 'Original historical note',
                            content_attributes: { voip_call_analysis: { summary: 'Summary', transcript: 'Transcript' } })
    external.create_voip_call_artifact!(conversation: conversation, message: note)
    expect { described_class.new(external: external).perform }.not_to change(Message, :count)
    expect(external.reload.call_message_id).to eq(note.id)
    expect(note.reload.content_type).to eq('voice_call')
    expect(note.content_attributes['voip_legacy_content']).to eq('Original historical note')
    external.update!(snapshot: snapshot.merge('state' => 'completed'))
    described_class.new(external: external).perform
    expect(note.reload.content_attributes['voip_call_analysis']).to eq('summary' => 'Summary', 'transcript' => 'Transcript')
    expect(note.content_attributes.dig('data', 'state')).to eq('completed')
  end

  it 'creates exactly one new conversation for an incoming call when enabled and not configured as single conversation' do
    service.credentials = { 'reopen_on_incoming' => true }
    service.save!
    expect { described_class.new(external: external).perform }.to change(Conversation, :count).by(1)
    expect(external.reload.conversation_id).not_to eq(conversation.id)
    expect(external.conversation).to be_open
    expect { described_class.new(external: external).perform }.not_to change(Conversation, :count)
    expect(conversation.reload).to be_resolved
  end

  it 'does not open a conversation when first learning a terminal call through REST recovery' do
    service.credentials = { 'reopen_on_incoming' => true }
    service.save!
    external.update!(snapshot: snapshot.merge('state' => 'missed'))
    expect { described_class.new(external: external).perform }.not_to change(Conversation, :count)
    expect(conversation.reload).to be_resolved
  end

  it 'keeps unmatched calls in history when automatic opening is off' do
    snapshot['from']['value'] = '5511999988888'
    external
    expect { described_class.new(external: external).perform }.not_to change(Contact, :count)
    expect(external.reload.call_message_id).to be_nil
    expect(account.conversations.count).to eq(1)
  end

  it 'keeps an already published recording note in its original conversation when automatic opening is later enabled' do
    service.credentials = { 'reopen_on_incoming' => true }
    service.save!
    note = create(:message, conversation: conversation, account: account, inbox: channel.inbox, private: true)
    external.create_voip_call_artifact!(conversation: conversation, message: note)
    conversation.resolved!
    expect { described_class.new(external: external).perform }.not_to change(Conversation, :count)
    expect(external.reload.conversation_id).to eq(conversation.id)
    expect(note.reload.conversation_id).to eq(conversation.id)
    expect(conversation.reload).to be_resolved
  end

  it 'uses only the principal inbox for partner inboxes and preserves one message across repeated events' do
    partner = create(:channel_whatsapp, account: account, phone_number: '+5566996222471', provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    WhatsappInboxLink.create!(account: account, primary_inbox: channel.inbox, secondary_inbox: partner.inbox,
                              default_provider: 'unoapi', enabled: true)
    external
    expect { described_class.new(external: external).perform }.to change(Message, :count).by(1)
    first_id = external.reload.call_message_id
    expect { described_class.new(external: external).perform }.not_to change(Message, :count)
    expect(external.reload.call_message_id).to eq(first_id)
    expect(external.call_message.inbox_id).to eq(channel.inbox.id)
    expect(partner.inbox.conversations).to be_empty
    expect(conversation.reload).to be_resolved
  end
end
