require 'rails_helper'

# File name is fixed by the regression-test ownership contract.
# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Whatsapp::UnifiedTransportService do
  let(:account) { create(:account) }
  let(:suffix) { SecureRandom.random_number(10**7).to_s.rjust(7, '0') }
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: "+55659#{suffix}",
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: "+556599#{suffix}",
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5565987654321') }
  let(:meta_alias) { create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: '556587654321') }
  let(:uno_alias) { create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '123456789012345@lid') }
  let!(:link) do
    WhatsappInboxLink.create!(account: account, primary_inbox: meta.inbox, secondary_inbox: uno.inbox,
                              default_provider: 'whatsapp_cloud', enabled: true)
  end
  let(:conversation) do
    create(:conversation, account: account, inbox: meta.inbox, contact: contact, contact_inbox: meta_alias)
  end
  let(:message) { build(:message, account: account, conversation: conversation, inbox: meta.inbox, message_type: :outgoing) }
  let(:service) { described_class.new(message: message) }

  it 'fails closed for every capability of an unknown provider' do
    expect(described_class.capabilities('unknown').values).to all(be(false))
    expect { described_class.prepare!(message: message, requested_provider: 'unknown') }
      .to raise_error(ArgumentError, /Unknown WhatsApp transport/)
  end

  it 'does not advertise remote deletion on either provider' do
    expect(described_class.capabilities('unoapi')['delete']).to be(false)
    expect(described_class.capabilities('whatsapp_cloud')['delete']).to be(false)
  end

  it 'keeps group messages on their existing channel rather than applying the direct-chat default' do
    conversation.update!(group: true, group_source_id: '123456789012345@g.us')
    described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud')
    expect(message.content_attributes['whatsapp_transport']).to be_nil
    expect(described_class.new(message: message, operation: 'reaction')).not_to be_enabled
  end

  { 'view_once' => { 'view_once' => true }, 'pix' => { 'whatsapp_interactive' => { 'type' => 'payment_request' } } }.each do |feature, attrs|
    it "routes #{feature} to Uno without changing the selected provider or default" do
      message.content_attributes = attrs
      described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud')
      message.save!

      expect(message.reload.content_attributes['whatsapp_transport']).to include(
        'requested_provider' => 'whatsapp_cloud', 'provider' => 'unoapi', 'inbox_id' => uno.inbox.id,
        'capability' => feature, 'reason' => 'capability_routing'
      )
      expect(service.inbox).to eq(uno.inbox)
      expect(link.reload.default_provider).to eq('whatsapp_cloud')
    end
  end

  it 'keeps the persisted selection when the configured default changes' do
    described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud')
    message.save!
    link.update!(default_provider: 'unoapi')

    expect(described_class.new(message: message.reload).inbox).to eq(meta.inbox)
    expect(message.content_attributes.dig('whatsapp_transport', 'provider')).to eq('whatsapp_cloud')
  end

  it 'rejects a delayed delivery after its link has been disabled' do
    described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud')
    message.save!
    link.update!(enabled: false)

    expect { described_class.new(message: message.reload).inbox }.to raise_error(ArgumentError, /link changed/)
  end

  it 'routes editing to Uno without mutating persisted transport metadata' do
    described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud')
    message.save!
    metadata = message.content_attributes.deep_dup

    expect(described_class.new(message: message, operation: 'edit').inbox).to eq(uno.inbox)
    expect(message.reload.content_attributes).to eq(metadata)
    expect(service.inbox).to eq(meta.inbox)
  end

  it 'overwrites forged transport metadata through the real message builder before saving' do
    params = ActionController::Parameters.new(
      content: 'Synthetic routing check', whatsapp_transport: 'whatsapp_cloud',
      content_attributes: { whatsapp_transport: { link_id: -1, provider: 'unoapi', inbox_id: uno.inbox.id } }
    )
    outgoing = Messages::MessageBuilder.new(create(:user, account: account), conversation, params).perform

    expect(outgoing.reload.content_attributes['whatsapp_transport']).to include(
      'link_id' => link.id, 'provider' => 'whatsapp_cloud', 'inbox_id' => meta.inbox.id, 'requested_provider' => 'whatsapp_cloud'
    )
    expect(outgoing.inbox_id).to eq(link.primary_inbox_id)
  end

  it 'prefers the actual provider contact alias over the shared phone' do
    described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud')
    expect(service.recipient).to eq(meta_alias.source_id)
  end

  it 'does not send a lid alias to Meta when the phone is known' do
    meta_alias.update!(source_id: '123456789012345@lid')
    described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud')
    expect(service.recipient).to eq('5565987654321')
  end

  it 'retains the native Uno lid recipient namespace' do
    uno_alias
    described_class.prepare!(message: message, requested_provider: 'unoapi')
    expect(service.recipient).to eq(uno_alias.source_id)
  end

  context 'when resolving public provider references' do
    let(:target) do
      build(:message, account: account, conversation: conversation, inbox: meta.inbox, source_id: 'wamid.direct',
                      content_attributes: { 'whatsapp_transport' => { 'inbox_id' => meta.inbox.id } })
    end

    before { described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud') }

    it 'rejects a different account even with matching direct transport metadata' do
      target.account = create(:account)
      expect { service.reference_for(target) }.to raise_error(ArgumentError, /not available in this conversation/)
    end

    it 'rejects a different conversation even with matching direct transport metadata' do
      target.conversation = create(:conversation, account: account, inbox: meta.inbox)
      expect { service.reference_for(target) }.to raise_error(ArgumentError, /not available in this conversation/)
    end

    it 'rejects private references even without unified transport enabled' do
      target.private = true
      message.content_attributes = {}
      expect { service.reference_for(target) }.to raise_error(ArgumentError, /not available in this conversation/)
    end

    it 'rejects web-only references even with matching direct transport metadata' do
      target.delivery_destination = 'web'
      expect { service.reference_for(target) }.to raise_error(ArgumentError, /not available in this conversation/)
    end

    it 'rejects a missing alias instead of returning an original or foreign provider ID' do
      target.content_attributes = {}
      target.save!
      expect { service.reference_for(target) }.to raise_error(ArgumentError, /not available in the selected provider/)
    end
  end

  context 'with Meta as the stored principal for a recent Uno incoming message' do
    let(:incoming) do
      create(:message, account: account, conversation: conversation, inbox: meta.inbox, sender: contact,
                       message_type: :incoming, content_attributes: { 'whatsapp_unified_message_id' => 'synthetic-ledger' })
    end
    let(:ledger) do
      WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: incoming, original_id: 'correlation-only',
                                     direction: 'incoming', participant_key: '5565987654321', message_kind: 'text')
    end
    let(:identity) do
      WhatsappMessageIdentity.create!(account: account, inbox: uno.inbox, channel: uno, provider: 'unoapi', external_id: 'uno-public-id',
                                      observations: { 'direction' => 'incoming', 'timestamp' => Time.current.to_i.to_s })
    end

    before do
      WhatsappUnifiedMessageAlias.create!(whatsapp_unified_message: ledger, whatsapp_message_identity: identity)
      described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud')
    end

    it 'does not let the canonical Meta inbox assignment renew the Meta reply window' do
      expect(service).not_to be_can_reply
    end

    it 'opens the window only after an actual Meta incoming alias is observed' do
      meta_identity = WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta, provider: 'whatsapp_cloud',
                                                      external_id: 'wamid.actual-meta', provider_message_id: 'correlation-only',
                                                      observations: { 'direction' => 'incoming', 'timestamp' => Time.current.to_i.to_s })
      WhatsappUnifiedMessageAlias.create!(whatsapp_unified_message: ledger, whatsapp_message_identity: meta_identity)

      expect(service.can_reply?).to be(true)
      expect(service.reference_for(incoming)).to eq('wamid.actual-meta')
    end

    it 'does not accept an expired Meta observation even when its canonical message is recent' do
      meta_identity = WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta, provider: 'whatsapp_cloud',
                                                      external_id: 'wamid.expired-meta',
                                                      observations: { 'direction' => 'incoming', 'timestamp' => 25.hours.ago.to_i.to_s })
      WhatsappUnifiedMessageAlias.create!(whatsapp_unified_message: ledger, whatsapp_message_identity: meta_identity)

      expect(service).not_to be_can_reply
    end
  end

  context 'with legacy Meta incoming messages' do
    before { described_class.prepare!(message: message, requested_provider: 'whatsapp_cloud') }

    it 'accepts a recent public channel message' do
      create(:message, account: account, conversation: conversation, inbox: meta.inbox, sender: contact, message_type: :incoming)
      expect(service.can_reply?).to be(true)
    end

    it 'ignores private messages' do
      create(:message, account: account, conversation: conversation, inbox: meta.inbox, sender: contact, message_type: :incoming, private: true)
      expect(service).not_to be_can_reply
    end

    it 'ignores web-only delivery' do
      conversation.inbox.update!(web_attendance_enabled: true)
      create(:message, account: account, conversation: conversation, inbox: meta.inbox, sender: contact,
                       message_type: :incoming, delivery_destination: 'web')
      expect(service).not_to be_can_reply
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
