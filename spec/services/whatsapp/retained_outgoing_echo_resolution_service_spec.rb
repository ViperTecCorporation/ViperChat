require 'rails_helper'

RSpec.describe Whatsapp::RetainedOutgoingEchoResolutionService do
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
    record = WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox,
                                       default_provider: 'unoapi', enabled: true)
    record.update!(activated_at: 1.minute.ago)
    record
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5566996526161', bsuid: '277425594347744@lid') }
  let!(:bsuid_alias) { create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: 'BR.1394780385973008') }
  let(:conversation) do
    alias_row = create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '5566996526161')
    create(:conversation, account: account, inbox: uno.inbox, contact: contact, contact_inbox: alias_row)
  end
  let(:capture) do
    { original: 'CE646E4FEBE80643FD7D', echo: 'e5bdee60-ccb6-11f1-96e6-c7915f0f4d0f',
      public: 'wamid.HBgTQlIuMTM5NDc4MDM4NTk3MzAwOBUUABEYFENFNjQ2RTRGRUJFODA2NDNGRDdEAA==' }
  end
  let!(:sent) do
    create(:message, account: account, inbox: uno.inbox, conversation: conversation, message_type: :outgoing, source_id: capture[:public],
                     content_attributes: { whatsapp_transport: { link_id: link.id, inbox_id: meta.inbox.id, provider: 'whatsapp_cloud',
                                                                 activation_cutoff: link.activated_at.iso8601(6), delivery_state: 'acknowledged' } })
  end
  let(:value) do
    { metadata: { display_phone_number: '5566996222471' },
      contacts: [{ wa_id: '5566996526161', user_id: '277425594347744@lid', profile: { name: 'Existing contact' } }],
      messages: [{ id: capture[:echo], provider_message_id: capture[:original], from: '5566996222471', type: 'text',
                   timestamp: Time.current.to_i.to_s, text: { body: 'synthetic echo' } }] }
  end
  let(:meta_identity) { WhatsappMessageIdentity.find_by!(inbox: meta.inbox, external_id: capture[:public]) }
  let(:uno_identity) { WhatsappMessageIdentity.find_by!(inbox: uno.inbox, external_id: capture[:echo]) }
  let(:retained_copy) do
    copy = create(:message, account: account, inbox: uno.inbox, conversation: conversation, message_type: :outgoing, source_id: capture[:echo])
    uno_identity.message_links.create_or_find_by!(message: copy)
    copy
  end
  let(:event) do
    WhatsappUnifiedEvent.create!(whatsapp_inbox_link: link, whatsapp_message_identity: uno_identity, activation_cutoff: link.activated_at,
                                 state: 'pending', reason: 'identity_pending', next_attempt_at: Time.current, payload: value)
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
    Whatsapp::MessageIdentityObservationService.new(inbox: meta.inbox, value: {}).observe_api_response(message: sent, external_id: capture[:public])
    WhatsappUnifiedMessageAlias.create!(whatsapp_message_identity: meta_identity, message: sent)
    Whatsapp::MessageIdentityObservationService.new(inbox: meta.inbox, value: {
                                                      statuses: [{ id: capture[:public], status: 'read', recipient_id: '556696526161' }]
                                                    }).perform
    Whatsapp::MessageIdentityObservationService.new(inbox: uno.inbox, value: value, outgoing_echo: true).perform
    Whatsapp::MessageIdentityObservationService.new(inbox: uno.inbox, value: {
                                                      statuses: [{ id: capture[:echo], status: 'delivered', recipient_id: '5566996526161' }]
                                                    }).perform
  end

  it 'uses an active BSUID alias and scoped receipt proof without rewriting observations' do
    original = [uno_identity.reload.attributes, meta_identity.reload.attributes]
    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: uno_identity, partner_inbox: meta.inbox)
    participant = Whatsapp::UnifiedParticipantService.new(inbox: uno.inbox, identity: uno_identity, link: link)
    expect(comparison.perform[:status]).to eq('participant_identity_pending')
    expect([participant.eligible?, participant.participant]).to eq([true, '5566996526161'])
    expect([uno_identity.reload.attributes, meta_identity.reload.attributes]).to eq(original)
  end

  it 'ingests a new recipientless echo into the API bubble without another message, contact or file' do
    snapshot = [Message.count, Contact.count, Attachment.count, ActiveStorage::Blob.count, sent.source_id]
    params = { entry: [{ changes: [{ value: value }] }] }.with_indifferent_access
    2.times { Whatsapp::IncomingMessageUnoapiService.new(inbox: uno.inbox, params: params, outgoing_echo: true).perform }
    expect([Message.count, Contact.count, Attachment.count, ActiveStorage::Blob.count, sent.reload.source_id]).to eq(snapshot)
    expect(Whatsapp::UnifiedMessageIngestionService.message_for(uno_identity)).to eq(sent)
    expect(WhatsappUnifiedMessage.where(whatsapp_inbox_link: link, original_id: capture[:original]).sole.message_id).to eq(sent.id)
  end

  context 'with an already retained duplicate bubble' do
    before { retained_copy }

    { '463' => { original: 'CE646E4FEBE80643FD7D', echo: 'e5bdee60-ccb6-11f1-96e6-c7915f0f4d0f',
                 public: 'wamid.HBgTQlIuMTM5NDc4MDM4NTk3MzAwOBUUABEYFENFNjQ2RTRGRUJFODA2NDNGRDdEAA==' },
      '468' => { original: 'CEF602230379654F1521', echo: '25355650-ccb7-11f1-96e6-c7915f0f4d0f',
                 public: 'wamid.HBgTQlIuMTM5NDc4MDM4NTk3MzAwOBUUABEYFENFRjYwMjIzMDM3OTY1NEYxNTIxAA==' } }.each do |real_event, observed|
      context "with event-#{real_event}" do
        let(:capture) { observed }

        it 'completes the pending event while keeping both bubbles, ids, contacts and media unchanged' do
          retained_copy.attachments.create!(account: account, file_type: :image,
                                            file: { io: StringIO.new('preserve-media'), filename: 'history.png', content_type: 'image/png' })
          snapshot = [sent.reload.attributes, retained_copy.reload.attributes, contact.reload.attributes, conversation.reload.attributes,
                      Attachment.all.map(&:attributes), ActiveStorage::Attachment.all.map(&:attributes), ActiveStorage::Blob.all.map(&:attributes)]
          captured = [uno_identity.reload.observations, meta_identity.reload.observations, event.payload]
          expect(Whatsapp::IncomingMessageUnoapiService).not_to receive(:new)
          expect(described_class.new(event: event).message).to eq(retained_copy)
          Whatsapp::UnifiedEventService.new(event: event).perform
          expect(event.reload).to have_attributes(state: 'completed', reason: 'correlated_existing_echo', attempts: 1, next_attempt_at: nil)
          expect([sent.reload.attributes, retained_copy.reload.attributes, contact.reload.attributes, conversation.reload.attributes,
                  Attachment.all.map(&:attributes), ActiveStorage::Attachment.all.map(&:attributes),
                  ActiveStorage::Blob.all.map(&:attributes)]).to eq(snapshot)
          expect([uno_identity.reload.observations, meta_identity.reload.observations, event.reload.payload]).to eq(captured)
          expect(Whatsapp::UnifiedMessageIngestionService.message_for(uno_identity)).to eq(retained_copy)
        end
      end
    end

    %w[receipt explicit_peer retired_alias missing_alias generation activation private other_conversation kind ambiguous].each do |problem|
      it "does not resolve contradictory or insufficient evidence: #{problem}" do
        case problem
        when 'receipt'
          uno_identity.update!(observations: uno_identity.observations.deep_merge('receipt_participants' => { 'recipient_id' => '5566991111111' }))
        when 'explicit_peer'
          meta_identity.update!(observations: meta_identity.observations.deep_merge('participants' => { 'to' => '5566991111111' }))
        when 'retired_alias' then bsuid_alias.update!(additional_attributes: { 'whatsapp_identity_retired' => { 'reason' => 'phone_changed' } })
        when 'missing_alias' then bsuid_alias.destroy!
        when 'generation'
          attributes = sent.content_attributes.deep_merge('whatsapp_transport' => { 'activation_cutoff' => 1.day.ago.iso8601(6) })
          sent.update!(content_attributes: attributes)
        when 'activation' then event.update!(activation_cutoff: link.activated_at - 1.second)
        when 'private' then retained_copy.update!(private: true)
        when 'other_conversation' then retained_copy.update!(conversation: create(:conversation, account: account, inbox: uno.inbox))
        when 'kind' then uno_identity.update!(observations: uno_identity.observations.merge('message_type' => 'image'))
        when 'ambiguous'
          WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta, provider: 'whatsapp_cloud',
                                          external_id: 'different-envelope', provider_message_id: capture[:original],
                                          observations: meta_identity.observations)
        end
        resolver = described_class.new(event: event)
        expect(resolver.message).to be_nil
        expect { expect(resolver.perform).to be(false) }.not_to change(WhatsappUnifiedMessageAlias, :count)
        expect(event.reload.state).to eq('pending')
      end
    end
  end
end
