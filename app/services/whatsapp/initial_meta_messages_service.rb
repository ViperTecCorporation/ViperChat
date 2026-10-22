# A pre-dispatch business rule, never a fallback following an external attempt.
class Whatsapp::InitialMetaMessagesService
  KEY = 'whatsapp_initial_meta_policy'.freeze

  def self.eligible_message?(message)
    Whatsapp::UnifiedTransportService.transport_message?(message) && message.sender.is_a?(User) &&
      message.additional_attributes.to_h['campaign_id'].blank? &&
      message.content_attributes.to_h.values_at('automation_rule_id', 'whatsapp_history_import', 'web_absence_request_key').none?(&:present?)
  end

  def self.capture!(message, link:)
    attributes = message.content_attributes.to_h.except(KEY)
    if link.meta_initial_messages_enabled? && link.meta_initial_messages_limit.positive? && eligible_message?(message)
      attributes[KEY] = { 'cycle' => message.conversation.web_attendance_cycle, 'limit' => link.meta_initial_messages_limit }
    end
    message.content_attributes = attributes
  end

  def initialize(message:)
    @message = message
    @conversation = message.conversation
  end

  def perform
    return unless self.class.eligible_message?(@message)
    return if @message.content_attributes.to_h[KEY].blank? || @message.content_attributes.to_h['whatsapp_transport'].blank?

    @message.with_lock do
      @conversation.with_lock { decide }
    end
  end

  private

  def decide
    policy = @message.content_attributes.to_h[KEY].to_h
    metadata = @message.content_attributes.to_h['whatsapp_transport'].to_h
    return if decision_started?(policy, metadata)

    @link = WhatsappInboxLink.for_inbox(@message.inbox)
    reason = ineligible_reason(policy, metadata)
    if reason == 'awaiting_customer_reply'
      transport = metadata.merge('provider' => 'unoapi', 'inbox_id' => @link.inbox_for('unoapi').id, 'reason' => reason)
      return record_decision(policy, reason, transport)
    end
    return record_decision(policy, reason) if reason

    apply_meta(policy, metadata)
  end

  def decision_started?(policy, metadata)
    policy['decision'].present? || @message.source_id.present? || metadata['delivery_attempt_id'].present? || metadata['fallback_from'].present?
  end

  def ineligible_reason(policy, metadata)
    return 'rule_disabled' unless active_rule?
    return 'link_changed' unless current_link?(metadata)
    return 'cycle_closed' if @conversation.resolved? || policy['cycle'] != @conversation.web_attendance_cycle

    meta_eligibility_reason(metadata)
  end

  def meta_eligibility_reason(metadata)
    return 'explicit_template' if metadata['capability'] == 'template'
    return 'capability_unsupported' unless Whatsapp::UnifiedTransportService.capabilities('whatsapp_cloud')[metadata['capability']]
    return 'awaiting_customer_reply' unless meta_transport(metadata).can_reply_in_current_cycle?

    'meta_unavailable' unless meta_available?(metadata)
  end

  def active_rule?
    @link&.meta_initial_messages_enabled? && @link.meta_initial_messages_limit.positive?
  end

  def current_link?(metadata)
    metadata['link_id'] == @link.id && metadata['activation_cutoff'] == @link.activated_at.iso8601(6)
  end

  def meta_available?(metadata)
    meta = @link.inbox_for('whatsapp_cloud')
    return false if !meta || meta.channel.reauthorization_required? || !@link.account.active?

    transport = meta_transport(metadata)
    transport.can_reply? && transport.recipient.present?
  rescue ArgumentError
    false
  end

  def meta_transport(metadata)
    attributes = { 'whatsapp_transport' => metadata.merge('provider' => 'whatsapp_cloud', 'inbox_id' => @link.inbox_for('whatsapp_cloud').id) }
    probe = Message.new(account: @message.account, inbox: @message.inbox, conversation: @conversation, content_attributes: attributes)
    Whatsapp::UnifiedTransportService.new(message: probe)
  end

  def apply_meta(policy, metadata)
    scope = WhatsappMetaCycleSlot.where(whatsapp_inbox_link: @link, conversation: @conversation,
                                        cycle: @conversation.web_attendance_cycle, activation_cutoff: @link.activated_at)
    position = scope.maximum(:position).to_i + 1
    limit = [policy['limit'].to_i, @link.meta_initial_messages_limit].min
    return record_decision(policy, 'limit_reached') if position > limit

    WhatsappMetaCycleSlot.create!(account: @message.account, whatsapp_inbox_link: @link, conversation: @conversation,
                                  message: @message, cycle: @conversation.web_attendance_cycle,
                                  activation_cutoff: @link.activated_at, position: position)
    transport = metadata.merge('provider' => 'whatsapp_cloud', 'inbox_id' => @link.inbox_for('whatsapp_cloud').id,
                               'reason' => 'initial_meta_messages')
    record_decision(policy.merge('position' => position), 'applied', transport)
  end

  def record_decision(policy, decision, transport = nil)
    attributes = @message.content_attributes.deep_dup
    attributes[KEY] = policy.merge('decision' => decision)
    attributes['whatsapp_transport'] = transport if transport
    # Routing metadata is internal, not another content/status event for bots or notifications.
    @message.update_columns(content_attributes: attributes) # rubocop:disable Rails/SkipsModelValidations
    return unless transport

    ScheduledMessageItem.where(message_id: @message.id).update_all(whatsapp_transport: transport) # rubocop:disable Rails/SkipsModelValidations
  end
end
