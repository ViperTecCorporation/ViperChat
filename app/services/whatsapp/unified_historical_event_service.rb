# Late counterparts/statuses belong to the original logical message even after
# unlink. This never starts a new ingestion or splits historical conversations.
class Whatsapp::UnifiedHistoricalEventService
  Held = Struct.new(:message)

  def initialize(inbox:, identity:)
    @inbox = inbox
    @identity = identity
  end

  def perform
    return unless @identity&.provider_message_id
    return Held.new(nil) if held_event?

    record = historical_record
    return unless record

    link = record.whatsapp_inbox_link
    return if current_generation?(record, link)
    return unless compatible?(record, link)

    reconcile_record(record)
  end

  private

  def historical_record
    scope = { account_id: @inbox.account_id, id: WhatsappInboxLink.covering(@inbox.id).select(:id) }
    records = WhatsappUnifiedMessage.joins(:whatsapp_inbox_link)
                                    .where(whatsapp_inbox_links: scope)
                                    .where(original_id: @identity.provider_message_id, direction: @identity.observations['direction']).to_a
    records.first if records.one?
  end

  def current_generation?(record, link)
    link.enabled? && record.created_at >= link.activated_at
  end

  def reconcile_record(record)
    record.with_lock do
      if record.message_id
        @participant_service.contact_link(record: record)
        record.aliases.create_or_find_by!(whatsapp_message_identity: @identity)
      else
        record.update!(state: 'review', lease_token: nil, lease_expires_at: nil)
      end
    end
    record
  end

  def held_event?
    event = WhatsappUnifiedEvent.where(whatsapp_message_identity: @identity).where.not(state: 'completed').first
    return false unless event

    link = event.whatsapp_inbox_link
    return false if event.state == 'pending' && link.enabled? && link.activated_at == event.activation_cutoff

    event.update!(state: 'review', reason: 'link_changed', next_attempt_at: nil) if event.state == 'pending'
    true
  end

  def compatible?(record, link)
    comparison = @participant_service = Whatsapp::UnifiedParticipantService.new(inbox: @inbox, identity: @identity, link: link)
    comparison.eligible? && comparison.participant == record.participant_key && record.message_kind == @identity.observations['message_type']
  end
end
