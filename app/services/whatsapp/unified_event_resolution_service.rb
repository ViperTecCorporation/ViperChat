# Resolve only an already persisted inbound message. Never replay provider IO,
# rewrite conflicting evidence, merge contacts or transfer/purge media.
class Whatsapp::UnifiedEventResolutionService
  def initialize(event:)
    @event = event
    @link = event.whatsapp_inbox_link
    @identity = event.whatsapp_message_identity
  end

  def message
    record = candidate
    record.message if record && !conflicting_alias?(record)
  end

  def perform
    record = candidate
    return false unless record

    record.with_lock do
      next false unless candidate&.id == record.id
      next false if conflicting_alias?(record)

      record.aliases.create_or_find_by!(whatsapp_message_identity: @identity)
      @event.update!(state: 'completed', reason: 'correlated', payload: {}, next_attempt_at: nil)
      true
    end
  end

  private

  def candidate
    @link.reload
    @identity.reload
    return unless eligible_scope?

    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @link.partner_for(@identity.inbox))
    return unless comparison.safe_for_unification? && verified_meta_envelope?

    rows = WhatsappUnifiedMessage.where(whatsapp_inbox_link: @link, original_id: @identity.provider_message_id, direction: 'incoming').to_a
    return unless rows.one?

    record = rows.first
    peer = comparison.comparison_participant
    return unless verified_candidate?(record, comparison, peer)

    record
  end

  def verified_candidate?(record, comparison, peer)
    verified_payload?(record, peer) && verified_record?(record, peer) &&
      comparison.contact_matches_participant?(record.message.conversation.contact) && verified_aliases?(record, peer)
  end

  def eligible_scope?
    @link.enabled? && @event.activation_cutoff == @link.activated_at &&
      @identity.provider == 'whatsapp_cloud' && @identity.account_id == @link.account_id &&
      @link.covers?(@identity.inbox) && @event.reason == 'correlation_conflict' && @identity.provider_message_id.present?
  end

  def verified_meta_envelope?
    parsed = Whatsapp::MetaMessageIdAdapter.parse(@identity.external_id)
    return false unless parsed && parsed['direction'] == 'incoming' && parsed['provider_message_id'] == @identity.provider_message_id

    adapter = @identity.observations.fetch('meta_id_adapter', {})
    adapter['status'] == 'recognized' && adapter['direction'] == 'incoming' && @identity.observations['direction'] == 'incoming'
  end

  def verified_payload?(record, peer)
    messages = Array(@event.payload.with_indifferent_access[:messages])
    messages.one? && messages.first[:id] == @identity.external_id && normalize(messages.first[:from]) == peer &&
      messages.first[:type] == record.message_kind
  end

  def verified_record?(record, peer)
    peer.present? && record.state == 'ready' && record.created_at >= @link.activated_at &&
      record.participant_key == peer && record.message_kind == @identity.observations['message_type'] && public_inbound?(record.message)
  end

  def public_inbound?(stored)
    stored&.incoming? && !stored.private? && !stored.web_attendance? && stored.account_id == @link.account_id &&
      stored.inbox_id == @link.primary_inbox_id && !stored.conversation.group?
  end

  def verified_aliases?(record, peer)
    record.identities.any? && record.identities.all? { |identity| identity.id == @identity.id || legacy_receipt_conflict?(identity, record, peer) }
  end

  def conflicting_alias?(record)
    existing = WhatsappUnifiedMessageAlias.find_by(whatsapp_message_identity: @identity)
    existing&.then { |row| row.whatsapp_unified_message_id != record.id || (row.message_id && row.message_id != record.message_id) }
  end

  def legacy_receipt_conflict?(identity, record, peer)
    observations = identity.observations
    legacy_scope?(identity, record) && legacy_conflicts?(observations) && receipt_matches?(observations, identity, peer) &&
      record.aliases.exists?(whatsapp_message_identity: identity)
  end

  def legacy_scope?(identity, record)
    identity.account_id == @link.account_id && identity.inbox_id == @link.partner_for(@identity.inbox).id &&
      identity.provider == 'unoapi' && identity.provider_message_id == record.original_id &&
      identity.observations['conflicting_provider_message_ids'].blank? && identity.observations['message_type'] == record.message_kind
  end

  def legacy_conflicts?(observations)
    conflicts = observations.fetch('conflicting_observations', {})
    conflicts.keys.sort == %w[direction participants.from] && Array(conflicts['direction']).sort == %w[incoming outgoing]
  end

  def receipt_matches?(observations, identity, peer)
    business = normalize(identity.inbox.channel.phone_number)
    return false unless normalize(observations['business_number']) == business
    return false unless receipt_from_matches?(observations, business, peer)

    participants = observations.fetch('participants', {})
    observations['direction'] == 'outgoing' && normalize(participants['from']) == business &&
      normalize(participants['recipient_id']) == peer && observations.fetch('statuses', {}).key?('sent')
  end

  def receipt_from_matches?(observations, business, peer)
    values = Array(observations.dig('conflicting_observations', 'participants.from')).map { |value| normalize(value) }
    values.none?(nil) && values.sort == [peer, business].sort
  end

  def normalize(value)
    Whatsapp::InboxLinkPhoneService.normalize(value)
  end
end
