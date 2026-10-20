require 'rails_helper'

RSpec.describe Whatsapp::CanonicalContactService do
  cases = [
    ['BR.1898499644457061', '556696092506', '5566996092506'],
    ['BR.2308917326612750', '556696263708', '5566996263708'],
    ['BR.1437204608379078', '556699112057', '5566999112057'],
    ['BR.1621807106141009', '556699579849', '5566999579849'],
    ['BR.1456245626424805', '556699657572', '5566999657572'],
    ['BR.1149624051333406', '556699676351', '5566999676351']
  ].freeze
  arrival_orders = %w[meta_first uno_first].freeze
  directions = %w[outgoing incoming].freeze

  let(:account) { create(:account) }
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              provider_config: { url: 'https://uno.invalid', api_key: 'synthetic' },
                              sync_templates: false, validate_provider_config: false)
  end

  around do |example|
    travel_to(Time.current.change(usec: 0)) { example.run }
  end

  %w[unoapi whatsapp_cloud].each do |primary|
    arrival_orders.each do |arrival|
      cases.each do |bsuid, meta_phone, canonical_phone|
        directions.each do |direction|
          it "preserves the old #{canonical_phone} contact with #{primary} primary and #{arrival} for #{direction}", :aggregate_failures do
            old = create(:contact, account: account, name: 'Nome antigo', phone_number: "+#{canonical_phone}", created_at: 2.years.ago)
            old_alias = create(:contact_inbox, inbox: uno.inbox, contact: old, source_id: canonical_phone)
            legacy = create(:contact, account: account, name: bsuid, bsuid: bsuid, phone_number: nil, created_at: 4.days.ago)
            create(:contact_inbox, inbox: meta.inbox, contact: legacy, source_id: bsuid)
            create(:contact_inbox, inbox: meta.inbox, contact: legacy, source_id: meta_phone)
            channels = { 'unoapi' => uno, 'whatsapp_cloud' => meta }
            link = WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(primary).inbox,
                                             secondary_inbox: channels.fetch(primary == 'unoapi' ? 'whatsapp_cloud' : 'unoapi').inbox,
                                             enabled: true, default_provider: 'unoapi')
            original = SecureRandom.hex(11).upcase
            flag = direction == 'outgoing' ? "\x11".b : "\x12".b
            encoded = "\x1c\x18".b + bsuid.bytesize.chr + bsuid + "\x15\x14\x00".b + flag + "\x18".b + original.bytesize.chr + original + "\x00".b
            events = {
              meta: { id: "wamid.#{Base64.strict_encode64(encoded)}", to: meta_phone, to_user_id: bsuid },
              uno: { id: SecureRandom.uuid, provider_message_id: original, to: canonical_phone }
            }
            preserved_fields = %w[id name phone_number bsuid additional_attributes created_at]
            snapshots = account.contacts.order(:id).map { |row| row.attributes.slice(*preserved_fields) }
            alias_snapshot = ContactInbox.where(inbox_id: account.inboxes.select(:id)).order(:id).pluck(:id, :contact_id, :source_id)
            order = arrival == 'meta_first' ? %i[meta uno] : %i[uno meta]
            2.times do
              order.each do |provider|
                channel = provider == :meta ? meta : uno
                event = events.fetch(provider).merge(from: channel.phone_number.delete_prefix('+'), timestamp: Time.current.to_i.to_s,
                                                     type: 'text', text: { body: 'Synthetic canonical routing' })
                if direction == 'incoming'
                  event = event.except(:to_user_id).merge(from: provider == :meta ? meta_phone : canonical_phone,
                                                          to: channel.phone_number.delete_prefix('+'))
                  event[:from_user_id] = bsuid if provider == :meta
                end
                value = { metadata: { display_phone_number: channel.phone_number.delete_prefix('+') } }
                value[direction == 'outgoing' ? :message_echoes : :messages] = [event]
                value[:contacts] = [{ wa_id: event[:from], profile: { name: 'Nome antigo' } }] if direction == 'incoming'
                params = { entry: [{ changes: [{ field: 'smb_message_echoes', value: value }] }] }.with_indifferent_access
                klass = provider == :meta ? Whatsapp::IncomingMessageWhatsappCloudService : Whatsapp::IncomingMessageUnoapiService
                klass.new(inbox: channel.inbox, params: params, outgoing_echo: direction == 'outgoing').perform
              end
            end
            messages = account.messages.where(message_type: direction)
            expect(messages.count).to eq(1)
            expect(messages.sole.conversation.contact_id).to eq(old.id)
            expect(messages.sole.inbox_id).to eq(link.primary_inbox_id)
            expect(messages.sole.sender_id).to eq(old.id) if direction == 'incoming'
            expect(WhatsappUnifiedMessageAlias.count).to eq(2)
            expect(account.contacts.order(:id).map { |row| row.attributes.slice(*preserved_fields) }).to eq(snapshots)
            expect(ContactInbox.where(id: alias_snapshot.map(&:first)).order(:id).pluck(:id, :contact_id, :source_id)).to eq(alias_snapshot)
            expect(old_alias.reload.contact_id).to eq(old.id)
          end
        end
      end
    end
  end
end
