require 'rails_helper'

RSpec.describe Whatsapp::InboxLinkTransportOptionsService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '5566996222471',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:link) { WhatsappInboxLink.create!(account: account, primary_inbox: uno, secondary_inbox: meta, default_provider: 'unoapi', enabled: true) }
  let(:conversation) { create(:conversation, account: account, inbox: uno) }
  let(:options) { link.transport_options(conversation) }

  before do
    Current.user = agent
    Current.account = account
    create(:inbox_member, inbox: uno, user: agent)
    create(:inbox_member, inbox: meta, user: agent)
  end

  after { Current.reset }

  it 'exposes only the approved fields and the shared capability matrix' do
    expect(options.keys).to contain_exactly(:link_id, :primary_inbox_id, :default_provider, :transports)
    expect(options[:transports].map { |row| row[:provider] }).to eq(%w[unoapi whatsapp_cloud])
    options[:transports].each do |row|
      expect(row.keys).to contain_exactly(:provider, :label, :inbox_id, :can_reply, :capabilities)
      expect(row[:capabilities]).to eq(Whatsapp::UnifiedTransportService.capabilities(row[:provider]))
    end
    expect(options.to_json).not_to include('provider_config', 'test_key', 'api_key')
  end

  it 'allows a principal-only agent to choose either transport without adding partner membership' do
    meta.inbox_members.where(user: agent).delete_all
    expect(options[:transports].map { |row| row[:inbox_id] }).to eq([uno.id, meta.id])
    expect(meta.inbox_members.where(user: agent)).not_to exist
  end

  it 'omits options on secondary historical conversations until principal access is explicitly granted' do
    uno.inbox_members.where(user: agent).delete_all
    historical = create(:conversation, account: account, inbox: meta, assignee: agent)
    expect(link.transport_options(historical)).to be_nil
    create(:inbox_member, inbox: uno, user: agent)
    expect(link.transport_options(historical)[:link_id]).to eq(link.id)
  end

  it 'allows account administrators without membership in either inbox' do
    Current.user = create(:user, account: account, role: :administrator)
    expect(options[:link_id]).to eq(link.id)
    expect(Current.user.inboxes.where(id: [uno.id, meta.id])).not_to exist
  end

  it 'uses the configured principal permission when Meta is primary' do
    link.update!(enabled: false)
    link.update!(primary_inbox: meta, secondary_inbox: uno, enabled: true)
    uno.inbox_members.where(user: agent).delete_all
    principal_conversation = create(:conversation, account: account, inbox: meta, assignee: agent)
    expect(link.transport_options(principal_conversation)[:primary_inbox_id]).to eq(meta.id)
    meta.inbox_members.where(user: agent).delete_all
    create(:inbox_member, inbox: uno, user: agent)
    expect(link.transport_options(principal_conversation)).to be_nil
  end

  it 'fails closed without principal permission, an account member or a user context' do
    uno.inbox_members.where(user: agent).delete_all
    expect(options).to be_nil
    Current.user = nil
    expect(link.transport_options(conversation)).to be_nil
    Current.user = create(:user)
    expect(link.transport_options(conversation)).to be_nil
  end

  it 'does not expose the selector for groups or disabled links' do
    conversation.update!(group: true)
    expect(options).to be_nil
    conversation.update!(group: false)
    link.update!(enabled: false)
    expect(link.transport_options(conversation)).to be_nil
  end

  it 'does not let public UnoAPI traffic, private notes or web activity open the Meta window' do
    conversation.inbox.update!(web_attendance_enabled: true)
    create(:message, account: account, inbox: uno, conversation: conversation, message_type: :incoming, delivery_destination: 'channel')
    create(:message, account: account, inbox: meta, conversation: conversation, message_type: :incoming, delivery_destination: 'web')
    create(:message, account: account, inbox: meta, conversation: conversation, message_type: :incoming, private: true)
    expect(options[:transports].find { |row| row[:provider] == 'whatsapp_cloud' }[:can_reply]).to be(false)
  end

  it 'requires an actual public incoming Meta message younger than 24 hours' do
    message = create(:message, account: account, inbox: meta, conversation: conversation, message_type: :incoming,
                               delivery_destination: 'channel', created_at: 25.hours.ago)
    expect(options[:transports].last[:can_reply]).to be(false)
    message.update!(created_at: 1.hour.ago)
    expect(link.transport_options(conversation)[:transports].last[:can_reply]).to be(true)
  end

  it 'recognizes Meta identity evidence on an incoming message stored in the primary inbox' do
    message = create(:message, account: account, inbox: uno, conversation: conversation, message_type: :incoming,
                               delivery_destination: 'channel')
    identity = WhatsappMessageIdentity.create!(account: account, inbox: meta, channel: meta.channel, provider: 'whatsapp_cloud',
                                               external_id: 'wamid.meta-incoming',
                                               observations: { direction: 'incoming', timestamp: 1.hour.ago.to_i.to_s })
    unified = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: message, original_id: 'original-incoming',
                                             participant_key: '5566991111111', message_kind: 'text', direction: 'incoming')
    WhatsappUnifiedMessageAlias.create!(whatsapp_unified_message: unified, whatsapp_message_identity: identity)
    expect(options[:transports].last[:can_reply]).to be(true)
  end

  it 'does not let a recent Uno-only canonical message in the Meta primary renew the Meta window' do
    link.update!(enabled: false)
    link.update!(primary_inbox: meta, secondary_inbox: uno, enabled: true)
    principal_conversation = create(:conversation, account: account, inbox: meta, assignee: agent)
    unified = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, original_id: 'uno-only-incoming',
                                             participant_key: '5566991111111', message_kind: 'text', direction: 'incoming')
    message = create(:message, account: account, inbox: meta, conversation: principal_conversation,
                               message_type: :incoming, delivery_destination: 'channel', created_at: 1.hour.ago,
                               content_attributes: { whatsapp_unified_message_id: unified.id })
    unified.update!(message: message)
    identity = WhatsappMessageIdentity.create!(account: account, inbox: uno, channel: uno.channel, provider: 'unoapi',
                                               external_id: 'uno-public-incoming',
                                               observations: { direction: 'incoming', timestamp: 1.hour.ago.to_i.to_s })
    WhatsappUnifiedMessageAlias.create!(whatsapp_unified_message: unified, whatsapp_message_identity: identity)

    meta_options = link.transport_options(principal_conversation)[:transports].find { |row| row[:provider] == 'whatsapp_cloud' }
    expect(meta_options[:can_reply]).to be(false)
  end
end
