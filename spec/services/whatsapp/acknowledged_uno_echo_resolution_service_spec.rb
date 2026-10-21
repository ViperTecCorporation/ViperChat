require 'rails_helper'

RSpec.describe Whatsapp::AcknowledgedUnoEchoResolutionService do
  let(:account) { create(:account) }
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let!(:link) do
    row = WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox,
                                    default_provider: 'unoapi', enabled: true)
    row.update!(activated_at: 1.minute.ago)
    row
  end
  let(:capture) do
    { original: '3EB08C60E314204722BF0D', uuid: 'f4241120-ccb4-11f1-b3c4-63718cf5742f',
      wamid: 'wamid.HBgTQlIuMjMzOTgxODMxMDA5MjMzNRUUABEYFjNFQjA4QzYwRTMxNDIwNDcyMkJGMEQA' }
  end
  let(:contact) { create(:contact, account: account, name: 'Marcos Vinicius', phone_number: '+5566999356516') }
  let!(:bsuid) { create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: 'BR.2339818310092335') }
  let(:conversation) do
    ci = create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '5566999356516')
    create(:conversation, account: account, inbox: uno.inbox, contact: contact, contact_inbox: ci)
  end
  let!(:sent) do
    create(:message, account: account, inbox: uno.inbox, conversation: conversation, message_type: :outgoing, source_id: capture[:uuid],
                     content_attributes: { whatsapp_transport: { link_id: link.id, inbox_id: uno.inbox.id, provider: 'unoapi',
                                                                 activation_cutoff: link.activated_at.iso8601(6), delivery_state: 'acknowledged' } })
  end
  let!(:uno_identity) do
    WhatsappMessageIdentity.create!(account: account, inbox: uno.inbox, channel: uno, provider: 'unoapi', external_id: capture[:uuid],
                                    provider_message_id: capture[:original],
                                    observations: { direction: 'outgoing', message_type: 'text', business_number: uno.phone_number,
                                                    participants: { from: '5566996222471' }, statuses: { sent: Time.current.to_i.to_s },
                                                    receipt_participants: { recipient_id: '5566999356516' } })
  end
  let(:value) do
    { metadata: { display_phone_number: '556696222471' }, contacts: [{ wa_id: '556699356516', user_id: bsuid.source_id }],
      message_echoes: [{ id: capture[:wamid], to: '556699356516', from: '556696222471', to_user_id: bsuid.source_id,
                         timestamp: Time.current.to_i.to_s, type: 'text', text: { body: 'synthetic event-460' } }] }
  end
  let(:meta_identity) { WhatsappMessageIdentity.find_by!(inbox: meta.inbox, external_id: capture[:wamid]) }
  let(:record) do
    WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, original_id: capture[:original], direction: 'outgoing',
                                   participant_key: '5566999356516', message_kind: 'text')
  end
  let(:event) do
    WhatsappUnifiedEvent.create!(whatsapp_inbox_link: link, whatsapp_message_identity: meta_identity, activation_cutoff: link.activated_at,
                                 state: 'pending', reason: 'correlation_conflict', next_attempt_at: Time.current, payload: value)
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
    uno_identity.message_links.create!(message: sent)
    WhatsappUnifiedMessageAlias.create!(whatsapp_message_identity: uno_identity, message: sent)
    Whatsapp::MessageIdentityObservationService.new(inbox: meta.inbox, value: value, outgoing_echo: true).perform
    record
  end

  it 'resolves real event-460 using its exact original ID, acknowledged send and equivalent receipt, preserving all stored data' do
    sent.attachments.create!(account: account, file_type: :image,
                             file: { io: StringIO.new('preserve-history'), filename: 'history.png', content_type: 'image/png' })
    snapshot = [sent.reload.attributes, conversation.reload.attributes, contact.reload.attributes, bsuid.reload.attributes,
                uno_identity.reload.attributes, meta_identity.reload.attributes, event.payload,
                Attachment.all.map(&:attributes), ActiveStorage::Attachment.all.map(&:attributes), ActiveStorage::Blob.all.map(&:attributes)]
    expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
    Whatsapp::UnifiedEventService.new(event: event).perform
    expect(event.reload).to have_attributes(state: 'completed', reason: 'correlated_existing_echo', attempts: 1, next_attempt_at: nil)
    expect(record.reload.message).to eq(sent)
    expect(Whatsapp::UnifiedMessageIngestionService.message_for(meta_identity)).to eq(sent)
    expect([sent.reload.attributes, conversation.reload.attributes, contact.reload.attributes, bsuid.reload.attributes,
            uno_identity.reload.attributes, meta_identity.reload.attributes, event.reload.payload,
            Attachment.all.map(&:attributes), ActiveStorage::Attachment.all.map(&:attributes),
            ActiveStorage::Blob.all.map(&:attributes)]).to eq(snapshot)
    expect { expect(described_class.new(event: event).perform).to be(false) }.not_to change(Message, :count)
  end

  it 'ingests a new Meta echo twice without a second bubble, contact or file' do
    counts = [Message.count, Contact.count, Attachment.count, ActiveStorage::Blob.count, sent.source_id]
    params = { entry: [{ changes: [{ value: value }] }] }.with_indifferent_access
    2.times { Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: meta.inbox, params: params, outgoing_echo: true).perform }
    expect(Whatsapp::UnifiedMessageIngestionService.message_for(meta_identity)).to eq(sent)
    expect([Message.count, Contact.count, Attachment.count, ActiveStorage::Blob.count, sent.reload.source_id]).to eq(counts)
  end

  %w[receipt missing_receipt explicit_peer contact generation acknowledgement private different_kind
     activation ambiguous payload business direction].each do |problem|
    it "refuses unsafe evidence without changing stored data: #{problem}" do
      case problem
      when 'receipt'
        uno_identity.update!(observations: uno_identity.observations.deep_merge('receipt_participants' => { 'recipient_id' => '5566991111111' }))
      when 'missing_receipt' then uno_identity.update!(observations: uno_identity.observations.except('receipt_participants'))
      when 'explicit_peer'
        uno_identity.update!(observations: uno_identity.observations.deep_merge('participants' => { 'to' => '5566991111111' }))
      when 'contact' then conversation.update!(contact: create(:contact, account: account, phone_number: '+5566991111111'))
      when 'generation'
        sent.update!(content_attributes: sent.content_attributes.deep_merge('whatsapp_transport' => { 'activation_cutoff' => 1.day.ago.iso8601(6) }))
      when 'acknowledgement'
        sent.update!(content_attributes: sent.content_attributes.deep_merge('whatsapp_transport' => { 'delivery_state' => 'attempting' }))
      when 'private' then sent.update!(private: true)
      when 'different_kind' then record.update!(message_kind: 'image')
      when 'activation' then event.update!(activation_cutoff: link.activated_at - 1.second)
      when 'ambiguous'
        WhatsappMessageIdentity.create!(account: account, inbox: uno.inbox, channel: uno, provider: 'unoapi', external_id: 'other-message',
                                        provider_message_id: capture[:original], observations: uno_identity.observations)
      when 'payload' then event.update!(payload: value.deep_merge(message_echoes: [{ id: 'different', type: 'text' }]))
      when 'business' then uno_identity.update!(observations: uno_identity.observations.merge('business_number' => '+5565991111111'))
      when 'direction' then uno_identity.update!(observations: uno_identity.observations.merge('direction' => 'incoming'))
      end
      snapshot = [sent.reload.attributes, contact.reload.attributes, record.reload.attributes, event.reload.attributes,
                  WhatsappUnifiedMessageAlias.count]
      resolver = described_class.new(event: event)
      expect(resolver.message).to be_nil
      expect(resolver.perform).to be(false)
      expect([sent.reload.attributes, contact.reload.attributes, record.reload.attributes, event.reload.attributes,
              WhatsappUnifiedMessageAlias.count]).to eq(snapshot)
    end
  end

  %w[image document].each do |kind|
    it "reuses the existing #{kind} attachment without fetching or duplicating media" do
      sent.attachments.create!(account: account, file_type: kind == 'image' ? :image : :file,
                               file: { io: StringIO.new('existing-media'), filename: 'existing.bin', content_type: 'application/octet-stream' })
      uno_identity.update!(observations: uno_identity.observations.merge('message_type' => kind))
      record.update!(message_kind: kind)
      payload = value.deep_dup
      payload[:message_echoes].first[:type] = kind
      payload[:message_echoes].first[kind.to_sym] = { id: 'do-not-download', mime_type: 'application/octet-stream' }
      meta_identity.update!(observations: meta_identity.observations.merge('message_type' => kind))
      snapshot = [Message.count, Contact.count, Attachment.all.map(&:attributes), ActiveStorage::Attachment.all.map(&:attributes),
                  ActiveStorage::Blob.all.map(&:attributes), sent.reload.attributes]
      params = { entry: [{ changes: [{ value: payload }] }] }.with_indifferent_access
      2.times { Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: meta.inbox, params: params, outgoing_echo: true).perform }
      expect(Whatsapp::UnifiedMessageIngestionService.message_for(meta_identity)).to eq(sent)
      expect([Message.count, Contact.count, Attachment.all.map(&:attributes), ActiveStorage::Attachment.all.map(&:attributes),
              ActiveStorage::Blob.all.map(&:attributes), sent.reload.attributes]).to eq(snapshot)
    end
  end
end
