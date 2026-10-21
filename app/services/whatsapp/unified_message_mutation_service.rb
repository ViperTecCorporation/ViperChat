# Edits/revokes are references to an existing bubble, never new message ingestion.
class Whatsapp::UnifiedMessageMutationService
  def self.mutation?(value)
    message = Array(value.with_indifferent_access[:messages] || value.with_indifferent_access[:message_echoes]).first
    message && (message[:type].in?(%w[edit revoke]) || message[:message_type] == 'message_edit')
  end

  def initialize(inbox:, value:)
    @inbox = inbox
    @value = value.with_indifferent_access
    @link = WhatsappInboxLink.for_inbox(inbox)
    @message = Array(@value[:messages] || @value[:message_echoes]).first
  end

  def perform
    return false unless @link && self.class.mutation?(@value)

    @identity = WhatsappMessageIdentity.find_by(account_id: @inbox.account_id, inbox_id: @inbox.id, external_id: @message[:id])
    return true unless @identity

    event = Whatsapp::UnifiedEventService.defer(link: @link, identity: @identity, value: @value, reason: 'mutation_target_pending')
    event.with_lock { process(event) { |target| yield(target, @message) } if event.state == 'pending' }
    true
  end

  private

  def process(event, &)
    return review(event, 'link_changed') unless @link.reload.enabled? && event.activation_cutoff == @link.activated_at
    return review(event, 'mutation_target_missing') if original_id.blank?

    candidates = target_messages
    return review(event, 'correlation_conflict') if candidates.many?
    return unless candidates.one? && verified_target?(candidates.first)

    apply(candidates.first, event, &)
  end

  def apply(target, event)
    target.with_lock do
      unless stale?(target)
        yield(target)
        target.update!(content_attributes: target.content_attributes.merge('whatsapp_mutation_timestamp' => mutation_timestamp))
      end
      event.update!(state: 'completed', reason: 'mutation_applied', payload: {}, next_attempt_at: nil)
    end
  end

  def stale?(target)
    # Revoke is terminal; provider timestamps may have different precision.
    return false if @message[:type] == 'revoke'

    mutation_timestamp < target.content_attributes['whatsapp_mutation_timestamp'].to_i ||
      target.content_attributes['deleted']
  end

  def original_id
    return @message.dig(:edit, :original_message_id).presence if @message[:type] == 'edit'
    return @message.dig(:revoke, :original_message_id).presence if @message[:type] == 'revoke'

    @message.dig(:context, :id).presence || @message.dig(:context, :message_id).presence || @message[:edited_message_id].presence
  end

  def target_messages
    identity = WhatsappMessageIdentity.find_by(account_id: @inbox.account_id, inbox_id: @inbox.id, external_id: original_id)
    if identity
      verifier = Whatsapp::MessageIdentityCorrelationService.new(identity: identity, partner_inbox: @link.partner_for(@inbox))
      return [] unless verifier.safe_for_unification?
    end
    targets = @inbox.messages.where(source_id: original_id).to_a
    if identity
      targets.concat(identity.messages.to_a)
      targets << Whatsapp::UnifiedMessageIngestionService.message_for(identity)
    end
    targets.concat(envelope_targets)
    targets.compact.uniq(&:id)
  end

  def envelope_targets
    return [] unless @inbox.channel.provider == 'whatsapp_cloud'

    parsed = Whatsapp::MetaMessageIdAdapter.parse(original_id)
    adapter = @identity.observations['meta_id_adapter'].to_h
    keys = %w[participant participant_type direction]
    return [] unless parsed && adapter['status'] == 'recognized' && parsed.values_at(*keys) == adapter.values_at(*keys)

    WhatsappUnifiedMessage.where(whatsapp_inbox_link: @link, original_id: parsed['provider_message_id'], direction: parsed['direction'],
                                 state: 'ready').includes(:message).filter_map(&:message)
  end

  def verified_target?(target)
    return false unless public_target?(target)
    return false unless target.message_type == @identity.observations['direction']

    verifier = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @link.partner_for(@inbox))
    verifier.safe_for_unification? && verifier.contact_matches_participant?(target.conversation.contact)
  end

  def public_target?(target)
    target.account_id == @link.account_id && [@link.primary_inbox_id, @link.secondary_inbox_id].include?(target.inbox_id) &&
      !target.private? && !target.conversation.group? && !target.web_attendance?
  end

  def mutation_timestamp
    @message[:edit_timestamp].present? ? @message[:edit_timestamp].to_i : @message[:timestamp].to_i * 1000
  end

  def review(event, reason)
    event.update!(state: 'review', reason: reason, next_attempt_at: nil)
  end
end
