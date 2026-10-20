require 'rails_helper'
require 'base64'
require 'tmpdir'

RSpec.describe Whatsapp::UnifiedMessageIngestionService, 'retained production echoes' do
  let(:account) { create(:account) }
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let!(:link) do
    WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox, enabled: true, default_provider: 'unoapi')
  end

  around do |example|
    travel_to(Time.current.change(usec: 0)) do
      Dir.mktmpdir('echo-pending-spec-') do |directory|
        example.metadata[:echo_storage] = directory
        example.run
      end
    end
  end

  before do
    disk = ActiveStorage::Service::DiskService.new(root: RSpec.current_example.metadata.fetch(:echo_storage))
    disk.name = ActiveStorage::Blob.service.name
    allow(ActiveStorage::Blob).to receive(:service).and_return(disk)
    allow(ActiveStorage::Blob.services).to receive(:fetch).and_return(disk)
  end

  cases = [
    [335, 'BR.2296667081155597', '5566999145190', '3EB052776A05DF21593A80', 'text'],
    [336, 'BR.2296667081155597', '5566999145190', '3EB0C1298C788C34B69F77', 'text'],
    [338, 'BR.2296667081155597', '5566999145190', '3EB0801F86EF5855BE1CD3', 'document'],
    [341, 'BR.2296667081155597', '5566999145190', '3EB0DE37F6B4D59C186A18', 'text'],
    [343, 'BR.2296667081155597', '5566999145190', '3EB01E3E997DC2D46F56BA', 'text'],
    [337, 'BR.4716460285239933', '5566999220064', '3EB0556543F4B38CE60B7D', 'text'],
    [339, 'BR.4716460285239933', '5566999220064', '3EB0C5FA367496343B7D0F', 'text'],
    [340, 'BR.4716460285239933', '5566999220064', '3EB0A846F304C48A735D4D', 'document'],
    [342, 'BR.4716460285239933', '5566999220064', '3EB03A940E4179B5DC683E', 'text'],
    [344, 'BR.4716460285239933', '5566999220064', '3EB0A380B82571FC10D264', 'text'],
    [348, 'BR.4716460285239933', '5566999220064', '3EB04908AB811796C5C932', 'text'],
    [370, 'BR.966391289854585', '5549991851558', '3EB0E9A0EFDE63B40BF48D', 'text']
  ]
  cases.each do |event_number, bsuid, phone, original, kind|
    it "completes event-#{event_number} without moving its legacy contact alias or downloading media" do
      old = create(:contact, account: account, phone_number: "+#{phone}", name: 'Preserved human', created_at: 2.years.ago)
      old_alias = create(:contact_inbox, inbox: uno.inbox, contact: old, source_id: phone)
      legacy = create(:contact, account: account, name: bsuid, bsuid: bsuid, phone_number: nil, created_at: 4.days.ago)
      alias_row = create(:contact_inbox, inbox: meta.inbox, contact: legacy, source_id: bsuid)
      conversation = create(:conversation, account: account, inbox: uno.inbox, contact: old, contact_inbox: old_alias)
      stored = create(:message, account: account, inbox: uno.inbox, conversation: conversation, message_type: :outgoing, source_id: SecureRandom.uuid)
      if kind == 'document'
        file = stored.attachments.build(account: account, file_type: :file)
        file.file.attach(io: StringIO.new('%PDF-synthetic'), filename: 'keep.pdf', content_type: 'application/pdf', identify: false)
        file.save!
      end
      ledger = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: stored, original_id: original,
                                              direction: 'outgoing', participant_key: phone, message_kind: kind, state: 'ready')
      uno_identity = WhatsappMessageIdentity.create!(account: account, inbox: uno.inbox, channel: uno, provider: 'unoapi',
        external_id: stored.source_id, provider_message_id: original, observations: {
          business_number: uno.phone_number, direction: 'outgoing', message_type: kind, timestamp: Time.current.to_i.to_s,
          participants: { from: '5566996222471', to: phone }
        })
      ledger.aliases.create!(whatsapp_message_identity: uno_identity)
      envelope = "\x1c\x18".b + bsuid.bytesize.chr + bsuid + "\x15\x14\x00\x11\x18".b + original.bytesize.chr + original + "\x00".b
      value = { metadata: { display_phone_number: '556696222471' }, message_echoes: [{
        id: "wamid.#{Base64.strict_encode64(envelope)}", from: '556696222471', to_user_id: bsuid,
        type: kind, text: { body: 'Synthetic replacement, no customer text' }, timestamp: Time.current.to_i.to_s
      }] }.with_indifferent_access
      Whatsapp::MessageIdentityObservationService.new(inbox: meta.inbox, value: value, outgoing_echo: true).perform
      identity = WhatsappMessageIdentity.find_by!(inbox: meta.inbox, provider_message_id: original)
      event = WhatsappUnifiedEvent.create!(whatsapp_inbox_link: link, whatsapp_message_identity: identity, payload: value,
                                           reason: 'identity_conflict', activation_cutoff: link.activated_at, state: 'pending', next_attempt_at: Time.current)
      before = [old.reload.attributes, legacy.reload.attributes, alias_row.reload.attributes, stored.reload.attributes,
                Attachment.order(:id).pluck(:id), ActiveStorage::Blob.order(:id).pluck(:id)]
      expect(Down).not_to receive(:download)
      2.times { Whatsapp::ProcessUnifiedEventJob.perform_now(event.id) }
      expect(event.reload.state).to eq('completed')
      expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity).id).to eq(stored.id)
      expect([old.reload.attributes, legacy.reload.attributes, alias_row.reload.attributes, stored.reload.attributes,
              Attachment.order(:id).pluck(:id), ActiveStorage::Blob.order(:id).pluck(:id)]).to eq(before)
      expect(account.messages.where(message_type: :outgoing).pluck(:id)).to eq([stored.id])
      expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
      if kind == 'document'
        expect { Whatsapp::ReconcileUnifiedMediaJob.perform_now(ledger.id) }.not_to change(ActiveStorage::Blob, :count)
        expect(ledger.reload.media_review_status).to eq('unchanged')
        blob_ids = ActiveStorage::Attachment.pluck(:id, :blob_id)
        legacy.update!(phone_number: '+5511987654321')
        expect(Whatsapp::UnifiedMediaReconciliationService.new(record: ledger).perform.status).to eq(:review)
        expect(ActiveStorage::Attachment.pluck(:id, :blob_id)).to eq(blob_ids)
        expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
      end
    end
  end

  [[372, '5566999636712', 'CE032B726F50E9E671A0'], [373, '5566996029356', 'CE920A3A5540883F2CCD']].each do |number, phone, original|
    variants = %w[text audio document].map { |kind| [kind, nil] } +
               %w[generation unacknowledged wrong_inbox contact source].map { |fault| ['text', fault] }
    variants.each do |kind, fault|
      it "checks event-#{number}'s Meta #{kind} echo, fault=#{fault || 'none'}, preserving source ID and files" do
        contact = create(:contact, account: account, phone_number: "+#{phone}")
        ci = create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: phone)
        conversation = create(:conversation, account: account, inbox: uno.inbox, contact: contact, contact_inbox: ci)
        raw_phone = phone.sub(/\A(55\d{2})9(\d{8})\z/, '\1\2')
        encoded = "\x1c\x18".b + raw_phone.bytesize.chr + raw_phone + "\x15\x02\x00\x11\x18".b + original.bytesize.chr + original + "\x00".b
        external = "wamid.#{Base64.strict_encode64(encoded)}"
        transport = { link_id: link.id, provider: 'unoapi', requested_provider: 'unoapi', inbox_id: uno.inbox.id,
                      activation_cutoff: link.activated_at.iso8601(6), delivery_state: 'acknowledged' }
        stored = create(:message, account: account, inbox: uno.inbox, conversation: conversation, message_type: :outgoing,
                                  source_id: external, content_attributes: { whatsapp_transport: transport })
        if kind != 'text'
          attachment = stored.attachments.build(account: account, file_type: kind == 'audio' ? :audio : :file)
          attachment.file.attach(io: StringIO.new('synthetic existing bytes'), filename: 'keep.bin', content_type: 'application/octet-stream', identify: false)
          attachment.save!
        end
        meta_identity = WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta, provider: 'whatsapp_cloud',
          external_id: external, provider_message_id: original, observations: {
            business_number: meta.phone_number, direction: 'outgoing', message_type: kind, timestamp: Time.current.to_i.to_s,
            participants: { from: meta.phone_number, to: raw_phone },
            meta_id_adapter: { status: 'recognized', direction: 'outgoing', participant: raw_phone, participant_type: 'phone' }
          })
        WhatsappUnifiedMessageAlias.create!(whatsapp_message_identity: meta_identity, message: stored)
        if fault
          attrs = stored.content_attributes.deep_dup
          attrs['whatsapp_transport']['activation_cutoff'] = 1.hour.ago.iso8601(6) if fault == 'generation'
          attrs['whatsapp_transport']['delivery_state'] = 'uncertain' if fault == 'unacknowledged'
          attrs['whatsapp_transport']['inbox_id'] = meta.inbox.id if fault == 'wrong_inbox'
          stored.update!(content_attributes: attrs)
          stored.update!(source_id: 'different-public-id') if fault == 'source'
          conversation.update!(contact: create(:contact, account: account, phone_number: '+5511987654321')) if fault == 'contact'
        end
        value = { metadata: { display_phone_number: '5566996222471' }, message_echoes: [{ id: SecureRandom.uuid,
          provider_message_id: original, from: '5566996222471', type: kind, text: { body: 'Synthetic echo' }, timestamp: Time.current.to_i.to_s }] }.with_indifferent_access
        Whatsapp::MessageIdentityObservationService.new(inbox: uno.inbox, value: value, outgoing_echo: true).perform
        identity = WhatsappMessageIdentity.find_by!(inbox: uno.inbox, provider_message_id: original)
        event = WhatsappUnifiedEvent.create!(whatsapp_inbox_link: link, whatsapp_message_identity: identity, payload: value,
          reason: 'correlation_conflict', activation_cutoff: link.activated_at, state: 'pending', next_attempt_at: Time.current)
        snapshot = [stored.reload.attributes, account.contacts.pluck(:id), Attachment.pluck(:id), ActiveStorage::Blob.pluck(:id)]
        expect(Down).not_to receive(:download)
        2.times { Whatsapp::ProcessUnifiedEventJob.perform_now(event.id) }
        if fault
          expect(event.reload.state).not_to eq('completed')
          expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity)).to be_nil
        else
          expect(event.reload.state).to eq('completed')
          expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity).id).to eq(stored.id)
        end
        expect([stored.reload.attributes, account.contacts.pluck(:id), Attachment.pluck(:id), ActiveStorage::Blob.pluck(:id)]).to eq(snapshot)
        expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
      end
    end
  end
end
