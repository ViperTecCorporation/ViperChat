# Existing legacy bubbles stay intact. Resolve only the exact, proven API-send/echo pair.
class Whatsapp::RetainedOutgoingEchoResolutionService
  def initialize(event:)
    @event = event
    @identity = event.whatsapp_message_identity
    @link = event.whatsapp_inbox_link
  end

  def message
    proof&.first
  end

  def perform
    pair = proof
    return false unless pair

    @event.with_lock do
      next false unless proof&.map(&:id) == pair.map(&:id)

      row = WhatsappUnifiedMessageAlias.create_or_find_by!(whatsapp_message_identity: @identity) { |alias_row| alias_row.message = pair.first }
      next false unless standalone_alias?(row, pair.first)

      @event.update!(state: 'completed', reason: 'correlated_existing_echo', next_attempt_at: nil)
      true
    end
  end

  private

  def proof
    @link.reload
    @identity.reload
    return unless eligible?
    return if WhatsappUnifiedMessage.exists?(whatsapp_inbox_link: @link, original_id: @identity.provider_message_id)

    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @link.partner_for(@identity.inbox))
    result = comparison.perform
    return unless %w[matched participant_identity_pending].include?(result[:status]) && result[:candidate_identity_ids].one?

    existing_pair(WhatsappMessageIdentity.find(result[:candidate_identity_ids].sole))
  end

  def existing_pair(counterpart)
    aliases = WhatsappUnifiedMessageAlias.where(whatsapp_message_identity: counterpart).where.not(message_id: nil).to_a
    copies = @identity.messages.where(source_id: @identity.external_id).to_a
    return unless aliases.one? && copies.one? && aliases.first.whatsapp_unified_message_id.nil?

    original = aliases.first.message
    copy = copies.first
    [copy, original] if verified_pair?(copy, original, counterpart)
  end

  def eligible?
    @event.state.in?(%w[pending review]) && @link.enabled? && @event.activation_cutoff == @link.activated_at && identity_scope? && payload_matches?
  end

  def identity_scope?
    @identity.provider == 'unoapi' && @identity.account_id == @link.account_id && @link.covers?(@identity.inbox) &&
      @identity.observations['direction'] == 'outgoing' && @identity.provider_message_id.present? &&
      @identity.external_id != @identity.provider_message_id
  end

  def standalone_alias?(row, message)
    row.message_id == message.id && row.whatsapp_unified_message_id.nil?
  end

  def payload_matches?
    payload = @event.payload.with_indifferent_access
    messages = Array(payload[:messages] || payload[:message_echoes])
    messages.one? && messages.first[:id] == @identity.external_id &&
      messages.first[:provider_message_id] == @identity.provider_message_id && messages.first[:type] == @identity.observations['message_type']
  end

  def verified_pair?(copy, original, counterpart)
    return false unless copy.id != original.id && copy.conversation_id == original.conversation_id &&
                        [copy, original].all? { |message| public_outgoing?(message) }

    verified_api_send?(original, counterpart)
  end

  def verified_api_send?(original, counterpart)
    verifier = Whatsapp::MessageIdentityCorrelationService.new(identity: counterpart, partner_inbox: @identity.inbox)
    metadata = original.content_attributes['whatsapp_transport'].to_h
    counterpart.provider == 'whatsapp_cloud' && original.source_id == counterpart.external_id &&
      metadata.values_at('link_id', 'inbox_id', 'provider', 'activation_cutoff', 'delivery_state') ==
        [@link.id, counterpart.inbox_id, 'whatsapp_cloud', @link.activated_at.iso8601(6), 'acknowledged'] &&
      verifier.safe_for_unification? && verifier.contact_matches_participant?(original.conversation.contact)
  end

  def public_outgoing?(message)
    primary_message?(message) &&
      message.outgoing? && !message.private? && !message.web_attendance? && !message.conversation.group? && message.created_at >= @link.activated_at
  end

  def primary_message?(message)
    message.account_id == @link.account_id && message.inbox_id == @link.primary_inbox_id &&
      message.conversation.account_id == @link.account_id && message.conversation.inbox_id == message.inbox_id
  end
end
