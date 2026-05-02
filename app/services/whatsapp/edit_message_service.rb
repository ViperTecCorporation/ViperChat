class Whatsapp::EditMessageService
  pattr_initialize [:message!, :content!]

  def perform
    return false unless editable_message?

    edit_event_id = channel.send_message_edit(whatsapp_recipient, message, content)
    return false if edit_event_id.blank?

    message.update!(
      content: content,
      content_attributes: edited_content_attributes(edit_event_id)
    )
    true
  end

  private

  def editable_message?
    message.outgoing? &&
      message.source_id.present? &&
      message.conversation.inbox.whatsapp? &&
      channel.provider == 'unoapi' &&
      content.to_s.strip.present?
  end

  def channel
    @channel ||= message.conversation.inbox.channel
  end

  def whatsapp_recipient
    return message.conversation.group_source_id if message.conversation.group?

    source_id = message.conversation.contact_inbox.source_id
    return source_id unless uuid_source_id?(source_id)

    message.conversation.contact_inbox.contact.phone_number&.delete_prefix('+').presence ||
      message.conversation.contact_inbox.contact.bsuid
  end

  def uuid_source_id?(source_id)
    source_id.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
  end

  def edited_content_attributes(edit_event_id)
    attrs = message.content_attributes.to_h.merge(
      'edited' => true,
      'edit_event_id' => edit_event_id,
      'edited_at' => Time.current.utc.iso8601
    )
    attrs['previous_content'] = message.content if message.content.present? && message.content != content
    attrs
  end
end
