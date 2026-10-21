# Scoped to the authorized event; no provider replay, contact merge or media IO.
require 'digest'

class Event460Maintenance
  MODELS = { contacts: Contact, contact_aliases: ContactInbox, conversations: Conversation, messages: Message,
             identities: WhatsappMessageIdentity, events: WhatsappUnifiedEvent,
             attachments: Attachment, storage: ActiveStorage::Attachment, blobs: ActiveStorage::Blob }.freeze
  EVENT_MUTABLE = %w[state reason attempts updated_at next_attempt_at].freeze

  def perform
    @phase = ENV.fetch('EVENT_460_PHASE', 'preview')
    raise 'Invalid phase' unless %w[preview apply verify].include?(@phase)

    ActiveRecord::Base.logger = nil
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY') unless @phase == 'apply'
      @event = WhatsappUnifiedEvent.find(460)
      verify_scope!
      @phase == 'verify' ? verify : maintain
    end
  end

  private

  def verify_scope!
    @identity = @event.whatsapp_message_identity
    raise 'Event scope changed' unless @event.whatsapp_inbox_link_id == 1 &&
                                       [@identity.id, @identity.account_id, @identity.inbox_id] == [26_022, 1, 65]
    raise 'Original ID changed' unless @identity.provider_message_id == '3EB08C60E314204722BF0D'
  end

  def verify
    previous = JSON.parse(File.read(ENV.fetch('EVENT_460_PREVIEW'))).fetch('inventory')
    verify_inventory!(previous)
    raise 'Event not resolved' unless @event.state == 'completed' && @event.reason == 'correlated_existing_echo'
    raise 'Wrong mapped message' unless Whatsapp::UnifiedMessageIngestionService.message_for(@identity)&.id == 2_498_876

    output(verified: true, event: 460, message: 2_498_876, preserved: previous.transform_values(&:size))
  end

  def maintain
    @snapshot = capture.as_json
    fingerprint = Digest::SHA256.hexdigest(@snapshot.to_json)
    resolver = Whatsapp::AcknowledgedUnoEchoResolutionService.new(event: @event)
    proposed = resolver.message&.id
    return output(fingerprint: fingerprint, proposed_message: proposed, inventory: @snapshot) if @phase == 'preview'

    apply(resolver, proposed, fingerprint)
  end

  def apply(resolver, proposed, fingerprint)
    raise 'Fresh preview fingerprint required' unless ENV.fetch('EVENT_460_FINGERPRINT') == fingerprint

    @event.lock!
    raise 'Expected exact existing bubble proof' unless proposed == 2_498_876
    raise 'Could not resolve event safely' unless resolver.perform

    @event.update!(attempts: @event.attempts + 1)
    verify_inventory!(@snapshot)
    raise 'Wrong canonical message' unless WhatsappUnifiedMessage.find(2198).message_id == 2_498_876

    output(applied: true, event: @event.slice(:id, :state, :reason, :attempts), message: 2_498_876,
           fingerprint: fingerprint, preserved: @snapshot.transform_values(&:size))
  end

  def capture
    snapshot = {
      contacts: rows(Contact.where(id: 94_129)),
      contact_aliases: rows(ContactInbox.where(contact_id: 94_129)),
      conversations: rows(Conversation.where(id: 37_692)),
      messages: rows(Message.where(conversation_id: 37_692)),
      identities: rows(WhatsappMessageIdentity.where(id: [26_019, 26_022])),
      events: [@event.attributes.except(*EVENT_MUTABLE)]
    }
    snapshot.merge(media(snapshot[:messages].pluck('id')))
  end

  def media(message_ids)
    attachments = rows(Attachment.where(message_id: message_ids))
    storage = rows(ActiveStorage::Attachment.where(record_type: 'Attachment', record_id: attachments.pluck('id')))
    { attachments: attachments, storage: storage, blobs: rows(ActiveStorage::Blob.where(id: storage.pluck('blob_id'))) }
  end

  def rows(scope)
    scope.order(:id).map(&:attributes)
  end

  def verify_inventory!(inventory)
    inventory.each do |key, saved|
      current = rows(MODELS.fetch(key.to_sym).where(id: saved.pluck('id'))).as_json
      current = current.map { |row| row.except(*EVENT_MUTABLE) } if key.to_s == 'events'
      raise "Preserved inventory changed: #{key}" unless current == saved
    end
  end

  def output(value)
    File.write(ENV.fetch('EVENT_460_RESULT'), JSON.pretty_generate(value))
  end
end

Event460Maintenance.new.perform
