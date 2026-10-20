require 'rails_helper'

RSpec.describe Whatsapp::UnifiedEventResolutionService do
  let(:account) { create(:account) }
  let(:uno) { create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471', sync_templates: false, validate_provider_config: false) }
  let(:meta) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471', sync_templates: false, validate_provider_config: false) }
  let!(:link) { WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox, default_provider: 'unoapi', enabled: true) }
  let(:contact) { create(:contact, account: account, phone_number: '+5566996269251') }
  let(:conversation) { create(:conversation, account: account, inbox: uno.inbox, contact: contact) }
  let!(:stored) { create(:message, :incoming, account: account, inbox: uno.inbox, conversation: conversation, source_id: 'legacy-uno-public-id') }
  let!(:record) { WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: stored, original_id: '3A004C30BA8EF3C134BF', direction: 'incoming', participant_key: '5566996269251', message_kind: 'audio', state: 'ready') }
  let!(:uno_identity) do
    WhatsappMessageIdentity.create!(account: account, inbox: uno.inbox, channel: uno, provider: 'unoapi', external_id: stored.source_id,
                                    provider_message_id: record.original_id, observations: {
                                      'direction' => 'outgoing', 'message_type' => 'audio', 'business_number' => uno.phone_number,
                                      'participants' => { 'from' => '5566996222471', 'recipient_id' => '5566996269251' },
                                      'statuses' => { 'sent' => '1792214073' },
                                      'conflicting_observations' => { 'direction' => %w[incoming outgoing],
                                                                      'participants.from' => %w[5566996269251 5566996222471] }
                                    })
  end
  let(:public_id) { 'wamid.HBgMNTU2Njk2MjY5MjUxFQIAEhgUM0EwMDRDMzBCQThFRjNDMTM0QkYA' }
  let!(:identity) do
    value = { messages: [{ id: public_id, from: '556696269251', type: 'audio', timestamp: '1792214063' }] }
    Whatsapp::MessageIdentityObservationService.new(inbox: meta.inbox, value: value).perform
    WhatsappMessageIdentity.find_by!(inbox: meta.inbox, external_id: public_id)
  end
  let!(:event) do
    WhatsappUnifiedEvent.create!(whatsapp_inbox_link: link, whatsapp_message_identity: identity, activation_cutoff: link.activated_at,
                                reason: 'correlation_conflict', state: 'pending', next_attempt_at: Time.current,
                                payload: { messages: [{ id: public_id, from: '556696269251', type: 'audio' }] })
  end
  let(:service) { described_class.new(event: event) }

  before do
    record.aliases.create!(whatsapp_message_identity: uno_identity)
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  it 'resolves the real event-1 shape without replaying, replacing evidence or touching media' do
    stored.attachments.create!(account: account, file_type: :audio,
                               file: { io: File.open(Rails.root.join('spec/assets/sample.ogg')), filename: 'sample.ogg', content_type: 'audio/ogg' })
    original_observations = uno_identity.observations.deep_dup
    snapshot = [Message.count, Contact.count, Attachment.count, ActiveStorage::Blob.count, stored.reload.attributes]
    expect_any_instance_of(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:perform)
    event.update!(state: 'review', next_attempt_at: nil, updated_at: 6.minutes.ago)
    Whatsapp::RecheckUnifiedEventsJob.perform_now
    expect(event.reload.state).to eq('pending')
    Whatsapp::ProcessUnifiedEventJob.perform_now(event.id)
    expect(event.reload).to have_attributes(state: 'completed', reason: 'correlated', attempts: 1, payload: {}, next_attempt_at: nil)
    expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity)).to eq(stored)
    expect(uno_identity.reload.observations).to eq(original_observations)
    expect([Message.count, Contact.count, Attachment.count, ActiveStorage::Blob.count, stored.reload.attributes]).to eq(snapshot)
    expect { Whatsapp::UnifiedEventService.new(event: event).perform }.not_to change(WhatsappUnifiedMessageAlias, :count)
  end

  it 'shows the proven conversation in review without creating an alias or modifying the event' do
    original = event.reload.attributes
    item = Whatsapp::UnifiedReviewService.new(link: link, actor: nil).list[:items].find { |row| row[:id] == "event-#{event.id}" }
    expect(item).to include(message_id: stored.id, conversation_id: conversation.id, conversation_display_id: conversation.display_id)
    expect(event.reload.attributes).to eq(original)
    expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity)).to be_nil
  end

  %w[contact kind direction private payload generation original_id extra_conflict recipient missing_receipt].each do |problem|
    it "keeps genuine or insufficient evidence for review: #{problem}" do
      case problem
      when 'contact' then contact.update!(phone_number: '+5566991111111')
      when 'kind' then record.update!(message_kind: 'image')
      when 'direction' then record.update!(direction: 'outgoing')
      when 'private' then stored.update!(private: true)
      when 'payload' then event.update!(payload: { messages: [{ id: 'other', from: '556696269251', type: 'audio' }] })
      when 'generation' then event.update!(activation_cutoff: link.activated_at - 1.second)
      when 'original_id' then uno_identity.update!(provider_message_id: 'other-original')
      when 'extra_conflict' then uno_identity.update!(observations: uno_identity.observations.deep_merge('conflicting_observations' => { 'message_type' => %w[audio image] }))
      when 'recipient' then uno_identity.update!(observations: uno_identity.observations.deep_merge('participants' => { 'recipient_id' => '5566991111111' }))
      when 'missing_receipt' then uno_identity.update!(observations: uno_identity.observations.except('statuses'))
      end
      expect(service.message).to be_nil
      expect { expect(service.perform).to be(false) }.not_to change(WhatsappUnifiedMessageAlias, :count)
      expect(event.reload.state).to eq('pending')
    end
  end
end
