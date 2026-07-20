class ScheduledMessages::Serializer
  def initialize(message, current_user)
    @message = message
    @current_user = current_user
  end

  def as_json
    serialized_items = items
    base_attributes.merge(
      conversation_id: @message.conversation.display_id,
      target_conversation_id: @message.target_conversation&.display_id,
      label: @message.label.slice(:id, :title, :color),
      contact: contact,
      inbox: @message.inbox.slice(:id, :name),
      messages: serialized_items,
      message_count: serialized_items.size,
      attachment_count: serialized_items.sum { |item| item[:attachment_blob_ids].size },
      sender: sender,
      created_by_id: @message.created_by_id,
      can_manage: can_manage?
    )
  end

  private

  def items
    @message.items.map do |item|
      item.as_json(only: [:id, :position, :status, :content, :content_type, :content_attributes, :voice_message,
                          :error_message, :message_id]).merge(attachment_blob_ids: item.signed_attachment_ids)
    end
  end

  def base_attributes
    @message.as_json(
      only: [:id, :scheduled_at, :status, :reason, :content, :content_type, :content_attributes,
             :attachment_blob_ids, :error_message]
    )
  end

  def contact
    { id: @message.contact.id, name: @message.contact.name, thumbnail: @message.contact.avatar_url }
  end

  def sender
    { id: @message.sender.id, name: @message.sender.name, email: @message.sender.email, avatar_url: @message.sender.avatar_url }
  end

  def can_manage?
    return true if @message.created_by_id == @current_user.id

    @message.account.account_users.find_by(user: @current_user)&.administrator?
  end
end
