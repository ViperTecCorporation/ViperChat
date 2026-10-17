# A durable reservation precedes ingestion/download. Existing public IDs are aliases,
# never rewritten. Events without reliable scope/evidence keep their legacy path.
class Whatsapp::UnifiedMessageIngestionService
  class Busy < StandardError; end
  SUPPORTED = %w[text image video audio document sticker location].freeze

  attr_reader :link, :record

  def initialize(inbox:, value:)
    @inbox = inbox
    @value = value.to_h.with_indifferent_access
    @link = WhatsappInboxLink.for_inbox(inbox)
    @activation_cutoff = @link&.activated_at
    @event = Array(@value[:messages] || @value[:message_echoes]).first&.with_indifferent_access
  end

  def perform(&)
    existing = mapped_message
    return synchronize_mapped_message(existing) if existing

    historical = Whatsapp::UnifiedHistoricalEventService.new(inbox: @inbox, identity: @identity).perform
    return historical.message if historical
    return if defer_changed_link?
    return yield(nil) unless eligible?
    return if defer_unready?

    ingest_reserved(&)
  rescue StandardError
    release_failed_attempt
    raise
  end

  def ingest_reserved
    reserve
    return defer_event('correlation_conflict') unless compatible?
    return record.message.tap { alias_service.merge_status } if acquire

    message = recovered_message || yield(self)
    complete(message)
    alias_service.merge_status if message
    message
  end

  def reserve
    @record = WhatsappUnifiedMessage.create_or_find_by!(
      whatsapp_inbox_link: link, original_id: @identity.provider_message_id, direction: @identity.observations['direction']
    ) do |row|
      row.participant_key = participant
      row.message_kind = @event[:type]
    end
  end

  def acquire
    @token = SecureRandom.uuid
    record.with_lock do
      alias_service.link_identity
      resolved_contact_link if record.message_id
      next true if record.message_id

      raise Busy, 'Canonical message ingestion in progress' if record.lease_expires_at && record.lease_expires_at > Time.current

      record.update!(state: 'processing', lease_token: @token, lease_expires_at: 5.minutes.from_now)
      false
    end
  end

  def complete(message)
    record.with_lock do
      raise Busy, 'Canonical lease changed' unless record.lease_token == @token

      if message&.persisted?
        record.update!(message: message, state: 'ready', lease_token: nil, lease_expires_at: nil,
                       media_inbox_id: message.attachments.exists? ? @inbox.id : nil)
      else
        record.update!(state: 'pending', lease_token: nil, lease_expires_at: nil)
      end
    end
  end

  def conversation(contact)
    primary = link.primary_inbox
    source_id = contact.phone_number&.delete_prefix('+').presence || @identity.observations.dig('meta_id_adapter', 'participant')
    raise ArgumentError, 'Unified contact requires a verified recipient' if source_id.blank?

    primary.with_lock do
      contact_link = principal_contact_link(primary, source_id, contact)
      scope = primary.conversations.non_group_conversations.where(contact_id: contact.id)
      scope = scope.where.not(status: :resolved) unless primary.lock_to_single_conversation?
      scope.reorder(created_at: :desc, id: :desc).first || primary.conversations.create!(
        account_id: primary.account_id, contact: contact, contact_inbox: contact_link
      )
    end
  end

  def ensure_owned!
    record.lock!
    raise Busy, 'Canonical ingestion lease was replaced' unless record.lease_token == @token
    raise Busy, 'Inbox link changed during ingestion' unless link.reload.enabled? && link.activated_at == @activation_cutoff
  end

  def resolved_contact_link
    participant_service.contact_link(record: record)
  end

  def self.message_for(identity)
    row = WhatsappUnifiedMessageAlias.find_by(whatsapp_message_identity: identity)
    row&.whatsapp_unified_message&.message || row&.message
  end

  private

  def synchronize_mapped_message(message)
    alias_service.merge_status if record
    message
  end

  def observed_identity
    return unless @event

    WhatsappMessageIdentity.find_by(inbox_id: @inbox.id, account_id: @inbox.account_id, external_id: @event[:id])
  end

  def mapped_message
    @identity = observed_identity
    return unless @identity

    alias_row = WhatsappUnifiedMessageAlias.find_by(whatsapp_message_identity: @identity)
    @record = alias_row&.whatsapp_unified_message
    return @record.message if @record&.message
    return alias_row&.message unless link && supported_event?

    nil
  end

  def defer_event(reason)
    Whatsapp::UnifiedEventService.defer(link: link, identity: @identity, value: @value, reason: reason)
    nil
  end

  def defer_changed_link?
    return false unless link && @identity && (!link.reload.enabled? || link.activated_at != @activation_cutoff)

    defer_event('link_changed')
    true
  end

  def defer_unready?
    reason = if participant.blank?
               'identity_pending'
             elsif awaiting_outbound_response?
               'outbound_response_pending'
             end
    return false unless reason

    defer_event(reason)
    true
  end

  def awaiting_outbound_response?
    return false unless @identity.observations['direction'] == 'outgoing'

    pending_outbound_messages?
  end

  def pending_outbound_messages?
    link.primary_inbox.messages.outgoing.where(source_id: nil, status: %i[progress sent], private: false, delivery_destination: 'channel')
        .where('created_at >= ?', link.activated_at).any? do |message|
      metadata = message.content_attributes['whatsapp_transport']
      metadata && metadata['link_id'] == link.id && metadata['activation_cutoff'] == link.activated_at.iso8601(6)
    end
  end

  def principal_contact_link(primary, source_id, contact)
    contact_link = primary.contact_inboxes.create_or_find_by!(source_id: source_id) { |row| row.contact = contact }
    raise ArgumentError, 'Conflicting primary contact alias' unless contact_link.contact_id == contact.id

    contact_link
  end

  def recovered_message
    link.primary_inbox.messages.with_content_attribute('whatsapp_unified_message_id', record.id.to_s).first
  end

  def release_failed_attempt
    return unless record && @token

    record.reload.with_lock do
      record.update!(state: 'pending', lease_token: nil, lease_expires_at: nil) if record.lease_token == @token
    end
  end

  def alias_service
    @alias_service ||= Whatsapp::UnifiedMessageAliasService.new(record: record, identity: @identity, inbox: @inbox)
  end

  def eligible?
    return false unless supported_event?

    return false unless @identity&.provider_message_id.present? && @identity.observations['direction'].in?(%w[incoming outgoing])

    participant_service.eligible?
  end

  def supported_event?
    active_link? && @event && SUPPORTED.include?(@event[:type]) && @event[:message_type].blank? &&
      @event[:timestamp].to_s.match?(/\A\d+\z/) && Time.zone.at(@event[:timestamp].to_i) >= link.activated_at
  end

  def active_link?
    link&.reload&.enabled?
  end

  def participant
    participant_service.participant
  end

  def participant_service
    @participant_service ||= Whatsapp::UnifiedParticipantService.new(inbox: @inbox, identity: @identity, link: link)
  end

  def compatible?
    alias_service.compatible?(participant: participant, message_kind: @event[:type])
  end
end
