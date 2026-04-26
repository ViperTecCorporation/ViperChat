class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    return if message.message_type == :outgoing && message.source_id&.is_present? # is message send by own

    should_send_template_message = template_params.present? || !message.conversation.can_reply?
    if should_send_template_message
      send_template_message
    else
      send_session_message
    end
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

    message_id = channel.send_template(
      whatsapp_recipient,
      {
        name: name,
        namespace: namespace,
        lang_code: lang_code,
        parameters: processed_parameters
      },
      message
    )
    message.update!(source_id: message_id) if message_id.present?
  end

  def send_session_message
    message_id = channel.send_message(whatsapp_recipient, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end

  def whatsapp_recipient
    return message.conversation.group_source_id if message.conversation.group?

    contact_inbox = message.conversation.contact_inbox
    source_id = contact_inbox.source_id
    return source_id unless uuid_source_id?(source_id)

    contact_inbox.contact.phone_number&.sub('+', '').presence || contact_inbox.contact.bsuid
  end

  def uuid_source_id?(source_id)
    source_id.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
  end
end
