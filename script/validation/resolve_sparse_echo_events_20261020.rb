# Scoped maintenance for the two authorized retained echoes. No provider IO or replay.
require 'digest'

ActiveRecord::Base.logger = nil
events = WhatsappUnifiedEvent.where(id: [463, 468]).order(:id).to_a
expected = { 463 => ['CE646E4FEBE80643FD7D', 2_498_979], 468 => ['CEF602230379654F1521', 2_498_992] }
raise 'Missing authorized events' unless events.map(&:id) == expected.keys

events.each do |event|
  identity = event.whatsapp_message_identity
  raise 'Event scope changed' unless event.whatsapp_inbox_link_id == 1 && identity.account_id == 1 && identity.inbox_id == 1
  raise 'Original ID changed' unless identity.provider_message_id == expected.fetch(event.id).first
end

snapshot = {
  contacts: Contact.where(id: [231, 62_583]).order(:id).map(&:attributes),
  contact_aliases: ContactInbox.where(contact_id: [231, 62_583]).order(:id).map(&:attributes),
  conversations: Conversation.where(id: 37_531).order(:id).map(&:attributes),
  messages: Message.where(id: [2_498_978, 2_498_979, 2_498_991, 2_498_992]).order(:id).map(&:attributes),
  identities: WhatsappMessageIdentity.where(id: [26_188, 26_190, 26_223, 26_225]).order(:id).map(&:attributes),
  events: events.map { |event| event.attributes.except('state', 'reason', 'attempts', 'updated_at', 'next_attempt_at') }
}
attachments = Attachment.where(message_id: snapshot[:messages].pluck('id')).order(:id).map(&:attributes)
storage = ActiveStorage::Attachment.where(record_type: 'Attachment', record_id: attachments.pluck('id')).order(:id).map(&:attributes)
snapshot[:attachments] = attachments
snapshot[:storage] = storage
snapshot[:blobs] = ActiveStorage::Blob.where(id: storage.pluck('blob_id')).order(:id).map(&:attributes)
fingerprint = Digest::SHA256.hexdigest(snapshot.to_json)

unless ENV['APPLY_SPARSE_ECHO_EVENTS'] == 'yes'
  proof = events.to_h do |event|
    message = Whatsapp::RetainedOutgoingEchoResolutionService.new(event: event).message ||
              Whatsapp::UnifiedMessageIngestionService.message_for(event.whatsapp_message_identity)
    [event.id, message&.id]
  end
  puts JSON.pretty_generate(fingerprint: fingerprint, proposed_messages: proof, inventory: snapshot)
  exit
end
raise 'Fresh preview fingerprint required' unless ENV.fetch('SPARSE_ECHO_FINGERPRINT') == fingerprint

WhatsappUnifiedEvent.transaction do
  events.each do |event|
    event.lock!
    if event.state == 'completed' && event.reason == 'correlated_existing_echo'
      row = WhatsappUnifiedMessageAlias.find_by!(whatsapp_message_identity: event.whatsapp_message_identity)
      raise 'Completed event points at a different message' unless row.message_id == expected.fetch(event.id).last

      next
    end

    resolver = Whatsapp::RetainedOutgoingEchoResolutionService.new(event: event)
    raise 'Existing echo proof changed' unless resolver.message&.id == expected.fetch(event.id).last
    raise 'Could not resolve event safely' unless resolver.perform

    event.update!(attempts: event.attempts + 1)
  end
  snapshot.each do |key, rows|
    next if key == :events

    models = { contacts: Contact, contact_aliases: ContactInbox, conversations: Conversation, messages: Message,
               identities: WhatsappMessageIdentity, attachments: Attachment, storage: ActiveStorage::Attachment, blobs: ActiveStorage::Blob }
    model = models.fetch(key)
    raise "Preserved inventory changed: #{key}" unless model.where(id: rows.pluck('id')).order(:id).map(&:attributes) == rows
  end
  raise 'Captured event evidence changed' unless events.map do |event|
    event.reload.attributes.except('state', 'reason', 'attempts', 'updated_at', 'next_attempt_at')
  end == snapshot[:events]

  puts JSON.pretty_generate(resolved: events.map { |event| event.attributes.slice('id', 'state', 'reason', 'attempts') },
                            preserved_messages: snapshot[:messages].pluck('id'), preservation_fingerprint: fingerprint)
end
