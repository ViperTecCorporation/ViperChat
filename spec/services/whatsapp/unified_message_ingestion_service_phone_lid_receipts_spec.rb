require 'rails_helper'

# Production event-5: the hosted LID belongs to the business, NOT the recipient.
# Keep this role distinction even though both providers deliver the same ID.
RSpec.describe Whatsapp::UnifiedMessageIngestionService do
  receipt_orders = [false, true].freeze
  let(:account) { create(:account) }
  let(:original_id) { '3EB0F3F5B37D5F6329094B' }
  let(:external_ids) do
    { uno: '3131aa00-ca0d-11f1-b3c4-63718cf5742f',
      meta: 'wamid.HBgTQlIuMTk4NTM2MDExODgwMzQ0MBUUABEYFjNFQjBGM0Y1QjM3RDVGNjMyOTA5NEIA' }
  end
  let(:meta_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno_channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              provider_config: { 'api_key' => 'synthetic', 'url' => 'https://uno.invalid' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:channels) { { meta: meta_channel, uno: uno_channel } }
  let!(:contact) { create(:contact, account: account, phone_number: '+5566996184404', bsuid: '112326346825774@lid') }

  before do
    create(:contact, account: account, phone_number: '+5566996222471', bsuid: '182222711709908@lid')
    create(:contact_inbox, inbox: uno_channel.inbox, contact: contact, source_id: '5566996184404')
    create(:contact_inbox, inbox: meta_channel.inbox, contact: contact, source_id: '556696184404')
  end

  around do |example|
    travel_to(Time.at(1_792_229_343).utc) { example.run }
  end

  def payload(provider, receipt: false)
    channel = channels.fetch(provider)
    event = { id: external_ids.fetch(provider), from: channel.phone_number.delete_prefix('+'),
              to: provider == :meta ? '556696184404' : '5566996184404', type: 'text',
              text: { body: 'Conteúdo de teste anonimizado' }, timestamp: Time.current.to_i.to_s }
    event[:provider_message_id] = original_id if provider == :uno
    event[:to_user_id] = 'BR.1985360118803440' if provider == :meta
    event = event.slice(:id, :timestamp, :provider_message_id).merge(status: 'sent', recipient_id: '182222711709908@hosted.lid') if receipt
    { entry: [{ changes: [{ field: receipt ? 'messages' : 'smb_message_echoes', value: {
      :metadata => { display_phone_number: channel.phone_number.delete_prefix('+') },
      (receipt ? :statuses : :message_echoes) => [event]
    } }] }] }.with_indifferent_access
  end

  def ingest(provider, receipt: false)
    service = provider == :meta ? Whatsapp::IncomingMessageWhatsappCloudService : Whatsapp::IncomingMessageUnoapiService
    service.new(inbox: channels.fetch(provider).inbox, params: payload(provider, receipt: receipt), outgoing_echo: !receipt).perform
  end

  %i[meta uno].each do |principal|
    context "with #{principal} as principal" do
      let!(:link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                  secondary_inbox: channels.fetch(principal == :meta ? :uno : :meta).inbox,
                                  default_provider: 'unoapi', enabled: true, activated_at: 1.day.ago)
      end

      it 'does not import a new contact from an Uno status-only device profile in a linked inbox' do
        receipt = payload(:uno, receipt: true)
        receipt.dig(:entry, 0, :changes, 0, :value)[:contacts] = [
          { wa_id: '', user_id: '778899001100@hosted.lid', profile: { name: 'Delivery device, not customer' } }
        ]
        previous = account.contacts.order(:id).map(&:attributes)

        expect do
          Whatsapp::IncomingMessageUnoapiService.new(inbox: uno_channel.inbox, params: receipt).perform
        end.not_to change(account.contacts, :count)
        expect(account.contacts.order(:id).map(&:attributes)).to eq(previous)
        expect(uno_channel.inbox.contact_inboxes.where(source_id: %w[778899001100@hosted.lid 778899001100@lid])).to be_empty
      end

      receipt_orders.each do |receipt_first|
        it "correlates the real Meta BSUID echo after the Uno echo, receipt_first=#{receipt_first}", :aggregate_failures do
          expect(Down).not_to receive(:download)
          ingest(:uno)
          canonical = WhatsappUnifiedMessage.find_by!(whatsapp_inbox_link: link, original_id: original_id).message
          preserved = [canonical.id, canonical.source_id, canonical.conversation_id, canonical.conversation.contact_id]
          contacts = account.contacts.order(:id).map(&:attributes)
          counts = [Message.count, Attachment.count, ActiveStorage::Blob.count]
          ingest(:uno, receipt: true) if receipt_first
          2.times { ingest(:meta) }
          ingest(:uno, receipt: true)
          ingest(:uno)

          ledger = WhatsappUnifiedMessage.find_by!(whatsapp_inbox_link: link, original_id: original_id)
          expect(ledger.reload.message_id).to eq(canonical.id)
          expect(ledger.identities.order(:provider).pluck(:external_id)).to eq([external_ids[:uno], external_ids[:meta]])
          expect([Message.count, Attachment.count, ActiveStorage::Blob.count]).to eq(counts)
          expect([canonical.reload.id, canonical.source_id, canonical.conversation_id, canonical.conversation.contact_id]).to eq(preserved)
          expect(canonical.inbox_id).to eq(channels.fetch(principal).inbox.id)
          expect(account.contacts.order(:id).map(&:attributes)).to eq(contacts)
          expect(WhatsappUnifiedEvent.where(whatsapp_inbox_link: link)).to be_empty
          expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
          identity = WhatsappMessageIdentity.find_by!(inbox: uno_channel.inbox, external_id: external_ids[:uno])
          expect(identity.observations.dig('participants', 'to')).to eq('5566996184404')
          expect(identity.observations.dig('receipt_participants', 'recipient_id')).to eq('182222711709908@hosted.lid')
        end
      end
    end
  end
end
