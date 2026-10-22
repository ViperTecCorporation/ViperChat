# A single alternate-provider attempt, only after a definitive rejection.
class Whatsapp::UnifiedDeliveryFallbackService
  KEY = Whatsapp::UnifiedDeliveryStateService::KEY
  SUCCESS = Whatsapp::UnifiedDeliveryStateService::SUCCESS

  def self.link_for(message, inbox: message.inbox)
    metadata = message.content_attributes.to_h['whatsapp_transport']
    return unless eligible_message?(message)
    return unless metadata.is_a?(Hash)

    link = WhatsappInboxLink.for_inbox(message.inbox)
    return unless link && link.account_id == message.account_id && link.covers?(inbox)

    link if current_activation?(link, metadata)
  end

  def self.current_activation?(link, metadata)
    metadata['link_id'] == link.id && metadata['activation_cutoff'] == link.activated_at.iso8601(6)
  end

  def self.eligible_message?(message)
    message.outgoing? && !message.private? && !message.conversation.group?
  end

  def initialize(message:)
    @message = message
  end

  def perform
    return unless potential_fallback?

    enqueue = @message.with_lock do
      @link = self.class.link_for(@message)
      next false unless @link

      attributes = @message.content_attributes.deep_dup
      metadata = attributes.fetch('whatsapp_transport')
      next true if metadata['fallback_pending'] && metadata['delivery_attempt_id'].blank?
      next false unless eligible_failure?(attributes, metadata)

      prepare_alternate(attributes, metadata)
    end
    SendReplyJob.perform_later(@message.id) if enqueue
  end

  private

  def potential_fallback?
    attributes = @message.content_attributes.to_h
    metadata = attributes.fetch('whatsapp_transport', {})
    metadata['fallback_pending'] || eligible_failure?(attributes, metadata)
  end

  def eligible_failure?(attributes, metadata)
    return false if metadata['fallback_from'].present? || metadata['delivery_state'] == 'attempting'

    failure = attributes.dig(KEY, metadata['provider']).to_h
    failure['state'] == 'failed' && failure['confirmed_failure']
  end

  def prepare_alternate(attributes, metadata)
    alternate = (Whatsapp::UnifiedTransportService::PROVIDERS - [metadata['provider']]).sole
    return false if delivered_or_observed_elsewhere?(attributes, alternate)

    target = @link.inbox_for(alternate)
    reason = unavailable_reason(target, alternate, metadata)
    if reason
      attributes['whatsapp_transport'] = metadata.merge('fallback_blocked_reason' => reason)
      save_summary(attributes)
      return false
    end

    schedule_alternate(attributes, metadata, alternate, target)
    true
  end

  def schedule_alternate(attributes, metadata, alternate, target)
    attributes['whatsapp_transport'] = metadata.except('delivery_attempt_id', 'delivery_attempted_at', 'provider_source_id').merge(
      'provider' => alternate, 'inbox_id' => target.id, 'reason' => 'provider_fallback',
      'fallback_from' => metadata['provider'], 'fallback_pending' => true, 'delivery_state' => 'pending'
    )
    attributes[KEY][alternate] = { 'state' => 'progress', 'origin' => 'fallback', 'updated_at' => Time.current.iso8601(6) }
    save_summary(attributes)
  end

  def unavailable_reason(target, provider, metadata)
    return 'provider_unavailable' unless target && @message.account.active? && !target.channel.reauthorization_required?
    return 'unsupported' unless Whatsapp::UnifiedTransportService.capabilities(provider)[metadata['capability']]

    probe = @message.dup
    probe.content_attributes = @message.content_attributes.merge(
      'whatsapp_transport' => metadata.merge('provider' => provider, 'inbox_id' => target.id)
    )
    transport = Whatsapp::UnifiedTransportService.new(message: probe)
    return 'template_required' if missing_template?(provider, transport)

    transport.recipient
    nil
  rescue ArgumentError
    'recipient_unavailable'
  end

  def missing_template?(provider, transport)
    provider == 'whatsapp_cloud' && !transport.can_reply? && @message.additional_attributes.to_h['template_params'].blank?
  end

  def delivered_or_observed_elsewhere?(attributes, alternate)
    outcomes = attributes.fetch(KEY, {})
    return true if outcomes.values.any? { |row| row['state'].in?(%w[delivered read]) }
    return true if outcomes.dig(alternate, 'state').in?(SUCCESS)

    # Proven aliases may predate the provider summaries. Never correlate by text.
    aliases = WhatsappUnifiedMessageAlias.left_joins(:whatsapp_unified_message)
                                         .where('whatsapp_unified_message_aliases.message_id = ? OR whatsapp_unified_messages.message_id = ?',
                                                @message.id, @message.id)
    aliases.includes(:whatsapp_message_identity).any? do |row|
      identity = row.whatsapp_message_identity
      identity.provider == alternate && observed_alternate?(attributes, identity)
    end
  end

  def observed_alternate?(attributes, identity)
    status = SUCCESS.find { |value| identity.observations.fetch('statuses', {}).key?(value) }
    return false unless status

    attributes[KEY][identity.provider] = { 'state' => status, 'origin' => 'observation', 'source_id' => identity.external_id }
    save_summary(attributes)
    true
  end

  def save_summary(attributes)
    Whatsapp::UnifiedDeliveryStateService.new(message: @message).save_summary!(attributes)
  end
end
