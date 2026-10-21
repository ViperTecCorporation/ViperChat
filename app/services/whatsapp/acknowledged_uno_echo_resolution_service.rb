# Resolve an exact Meta echo of an acknowledged Uno API send without replay or media IO.
class Whatsapp::AcknowledgedUnoEchoResolutionService
  def initialize(event:)
    @event = event
    @identity = event.whatsapp_message_identity
    @link = event.whatsapp_inbox_link
  end

  def message
    proof&.last
  end

  def perform
    pair = proof
    return false unless pair

    pair.first.with_lock do
      next false unless proof&.map(&:id) == pair.map(&:id)

      service = Whatsapp::UnifiedMessageAliasService.new(record: pair.first, identity: @identity, inbox: @identity.inbox)
      service.link_identity
      @event.update!(state: 'completed', reason: 'correlated_existing_echo', next_attempt_at: nil)
      true
    end
  end

  private

  def proof
    @link.reload
    @identity.reload
    return unless eligible?

    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @link.partner_for(@identity.inbox))
    return unless comparison.safe_for_unification?

    result = comparison.perform
    return unless %w[matched participant_identity_pending].include?(result[:status]) && result[:candidate_identity_ids].one?

    record = pending_record
    return unless record

    verified_pair(record, result[:candidate_identity_ids], comparison)
  end

  def pending_record
    records = WhatsappUnifiedMessage.where(whatsapp_inbox_link: @link, original_id: @identity.provider_message_id, direction: 'outgoing').to_a
    records.sole if records.one? && records.first.message_id.nil?
  end

  def verified_pair(record, candidate_ids, comparison)
    rows = WhatsappUnifiedMessageAlias.where(whatsapp_message_identity_id: candidate_ids).where.not(message_id: nil).to_a
    return unless rows.one? && rows.sole.whatsapp_message_identity.provider == 'unoapi'
    return if WhatsappUnifiedMessageAlias.exists?(whatsapp_message_identity: @identity)

    message = rows.sole.message
    service = Whatsapp::UnifiedMessageAliasService.new(record: record, identity: @identity, inbox: @identity.inbox)
    metadata = message.content_attributes['whatsapp_transport'].to_h
    return unless metadata['provider'] == 'unoapi' && metadata['delivery_state'] == 'acknowledged' &&
                  service.compatible?(participant: comparison.comparison_participant, message_kind: @identity.observations['message_type'])

    [record, message]
  end

  def eligible?
    @event.state.in?(%w[pending review]) && @link.enabled? && @event.activation_cutoff == @link.activated_at &&
      identity_scope? && verified_envelope? && verified_payload?
  end

  def identity_scope?
    @identity.account_id == @link.account_id && @link.covers?(@identity.inbox) && @identity.provider == 'whatsapp_cloud' &&
      @identity.observations['direction'] == 'outgoing' && @identity.provider_message_id.present?
  end

  def verified_envelope?
    parsed = Whatsapp::MetaMessageIdAdapter.parse(@identity.external_id)
    parsed && parsed['direction'] == 'outgoing' && parsed['provider_message_id'] == @identity.provider_message_id
  end

  def verified_payload?
    messages = Array(@event.payload.with_indifferent_access[:message_echoes])
    messages.one? && messages.first[:id] == @identity.external_id && messages.first[:type] == @identity.observations['message_type']
  end
end
