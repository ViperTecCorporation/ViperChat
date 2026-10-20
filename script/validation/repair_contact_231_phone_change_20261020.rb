# Authorized maintenance only for account 1/contact 231/event 486. No merge, send or purge.
require 'digest'

ActiveRecord::Base.logger = nil
contact = Contact.find_by!(id: 231, account_id: 1)
event = WhatsappUnifiedEvent.find(486)
old_lid = '242309471989955@lid'
new_phone = '+5566996803524'
original_id = '3EB0110B8308CA4CD017DE'
raise 'Contact phone changed since authorization' unless contact.phone_number == new_phone
raise 'Unexpected current identity' unless [nil, old_lid].include?(contact.bsuid)

identity = event.whatsapp_message_identity
raise 'Event scope changed' unless identity.account_id == 1 && identity.provider_message_id == original_id
raise 'Event recipient changed' unless identity.observations.dig('participants', 'to') == '556699367556'

aliases = contact.contact_inboxes.order(:id).to_a
raise 'Contact aliases changed; review a new preview' unless aliases.map(&:id) == [231, 13_510, 14_673, 98_444, 103_074, 114_286]
raise 'Unexpected alias owner' unless aliases.all? { |row| [1, 18, 19].include?(row.inbox_id) }
raise 'Unexpected alias identity' unless aliases.all? { |row| [new_phone.delete_prefix('+'), old_lid].include?(row.source_id) }

snapshot = { contact: contact.attributes, aliases: aliases.map(&:attributes), event: event.attributes, identity: identity.attributes }
fingerprint = Digest::SHA256.hexdigest(snapshot.to_json)
if ENV['APPLY_CONTACT_231'] != 'yes'
  puts JSON.pretty_generate(snapshot.merge(fingerprint: fingerprint, retire_alias_ids: aliases.select { |row| row.source_id == old_lid }.map(&:id)))
  exit
end
raise 'Fresh preview fingerprint required' unless ENV.fetch('CONTACT_231_FINGERPRINT') == fingerprint

Contact.transaction do
  ([contact, event] + aliases).each(&:lock!)
  current = { contact: contact.attributes, aliases: aliases.map(&:attributes), event: event.attributes, identity: identity.reload.attributes }
  raise 'Data changed after preview' unless Digest::SHA256.hexdigest(current.to_json) == fingerprint

  conversations = contact.conversations.order(:id).map(&:attributes)
  messages = Message.where(conversation_id: conversations.pluck('id')).order(:id).map(&:attributes)
  attachments = Attachment.where(message_id: messages.pluck('id')).order(:id).map(&:attributes)
  storage = ActiveStorage::Attachment.where(record_type: 'Attachment', record_id: attachments.pluck('id')).order(:id).map(&:attributes)
  blobs = ActiveStorage::Blob.where(id: storage.pluck('blob_id')).order(:id).map(&:attributes)
  inventory = [conversations, messages, attachments, storage, blobs]

  change = { 'from' => '+5566999367556', 'to' => new_phone, 'at' => Time.current.iso8601(6), 'bsuid' => old_lid,
             'reason' => 'administrator_confirmed_same_person_new_phone', 'event_id' => 486 }
  aliases.select { |row| row.source_id == old_lid }.each do |row|
    row.update!(additional_attributes: row.additional_attributes.merge('whatsapp_identity_retired' => change))
  end
  changes = Array(contact.additional_attributes['whatsapp_phone_changes']) + [change]
  attributes = contact.additional_attributes.merge('whatsapp_phone_changes' => changes)
  contact.update_columns(bsuid: nil, whatsapp_username: nil, additional_attributes: attributes, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

  # This echo really names the cancelled number. Archive the reviewed conflict, do not fake a match.
  event.update!(state: 'disabled', reason: 'retired_recipient_after_phone_change', next_attempt_at: nil)
  raise 'Captured payload changed' unless event.payload == snapshot[:event]['payload']
  raise 'Captured provider evidence changed' unless identity.reload.attributes == snapshot[:identity]

  after = [Conversation.where(id: conversations.pluck('id')).order(:id).map(&:attributes),
           Message.where(id: messages.pluck('id')).order(:id).map(&:attributes),
           Attachment.where(id: attachments.pluck('id')).order(:id).map(&:attributes),
           ActiveStorage::Attachment.where(id: storage.pluck('id')).order(:id).map(&:attributes),
           ActiveStorage::Blob.where(id: blobs.pluck('id')).order(:id).map(&:attributes)]
  raise 'Historical inventory changed; transaction rolled back' unless inventory == after

  puts JSON.pretty_generate(contact_id: contact.id, phone_number: contact.phone_number, bsuid: contact.bsuid,
                            retired_alias_ids: aliases.select(&:whatsapp_identity_retired?).map(&:id),
                            event_id: event.id, event_state: event.state, reason: event.reason,
                            preserved_counts: inventory.map(&:length), history_sha256: Digest::SHA256.hexdigest(inventory.to_json))
end
