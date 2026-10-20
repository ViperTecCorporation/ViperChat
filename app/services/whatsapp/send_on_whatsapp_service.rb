class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def unified_transport
    @unified_transport ||= Whatsapp::UnifiedTransportService.new(message: message)
  end

  def inbox
    unified_transport.enabled? ? unified_transport.inbox : super
  end

  def can_reply_on_transport?
    unified_transport.enabled? ? unified_transport.can_reply? : message.conversation.can_reply?
  end

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    Whatsapp::InitialMetaMessagesService.new(message: message).perform
    @unified_transport = nil
    if selected_meta_template_missing?
      message.update!(status: :failed, external_error: 'The selected Meta transport requires an approved template outside its reply window')
      return
    end
    return send_web_invitation if message.content_attributes['web_attendance_invitation_id'].present?

    return if message.message_type == :outgoing && message.source_id&.is_present? # is message send by own

    if should_send_template_message?
      send_template_message
    else
      send_session_message
    end
  end

  def selected_meta_template_missing?
    unified_transport.enabled? && template_required? && !can_reply_on_transport? && template_params.blank?
  end

  def should_send_template_message?
    template_params.present? || (template_required? && !can_reply_on_transport?)
  end

  def send_web_invitation
    unless can_reply_on_transport?
      message.update!(status: :failed, external_error: 'The WhatsApp reply window is closed; an approved template is required')
      return
    end

    send_session_message
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    recipient = nil
    Whatsapp::UnifiedDeliveryAttemptService.new(message: message).perform(preflight: -> { recipient = whatsapp_recipient }) do
      message_id = channel.send_template(
        recipient || whatsapp_recipient,
        { name: name, namespace: namespace, lang_code: lang_code, parameters: processed_parameters },
        message
      )
      persist_source_id(message_id)
    end
  end

  def send_session_message
    recipient = nil
    preflight = lambda do
      recipient = whatsapp_recipient
      unified_transport.reply_context if unified_transport.enabled?
    end
    Whatsapp::UnifiedDeliveryAttemptService.new(message: message).perform(preflight: preflight) do
      message_id = channel.send_message(recipient || whatsapp_recipient, message)
      persist_source_id(message_id)
    end
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end

  def template_required?
    channel.provider != 'unoapi'
  end

  def persist_source_id(message_id)
    return if message_id.blank?

    dedup_lock = Whatsapp::MessageDedupLock.new("#{inbox.id}:#{message_id}")
    dedup_lock.acquire!
    Message.transaction do
      message.update!(source_id: message_id)
      unified_transport.register_source_id!(message_id)
    end
  ensure
    dedup_lock&.release!
  end

  def whatsapp_recipient
    return unified_transport.recipient if unified_transport.enabled?

    return message.conversation.group_source_id if message.conversation.group?

    contact_inbox = message.conversation.contact_inbox.reload
    return recipient_for_retired_identity if contact_inbox.whatsapp_identity_retired?

    source_id = contact_inbox.source_id
    return source_id unless uuid_source_id?(source_id)

    contact_inbox.contact.phone_number&.sub('+', '').presence || contact_inbox.contact.bsuid
  end

  def uuid_source_id?(source_id)
    source_id.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
  end

  def recipient_for_retired_identity
    Whatsapp::OutboundRecipientService.new(conversation: message.conversation, inbox: message.inbox).perform
  end
end
