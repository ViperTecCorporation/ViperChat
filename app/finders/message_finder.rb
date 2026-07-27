class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    cursor = messages.find_by(id: after_id)
    return messages.none unless cursor

    messages
      .where('created_at > ? OR (created_at = ? AND id > ?)', cursor.created_at, cursor.created_at, cursor.id)
      .reorder(created_at: :asc, id: :asc)
      .limit(100)
  end

  def messages_before(before_id)
    cursor = messages.find_by(id: before_id)
    return messages.none unless cursor

    messages
      .where('created_at < ? OR (created_at = ? AND id < ?)', cursor.created_at, cursor.created_at, cursor.id)
      .reorder(created_at: :desc, id: :desc)
      .limit(20)
      .reverse
  end

  def messages_between(after_id, before_id)
    after_cursor = messages.find_by(id: after_id)
    before_cursor = messages.find_by(id: before_id)
    return messages.none unless after_cursor && before_cursor

    messages
      .where('created_at > ? OR (created_at = ? AND id >= ?)', after_cursor.created_at, after_cursor.created_at, after_cursor.id)
      .where('created_at < ? OR (created_at = ? AND id < ?)', before_cursor.created_at, before_cursor.created_at, before_cursor.id)
      .reorder(created_at: :asc, id: :asc)
      .limit(1000)
  end

  def messages_latest
    messages.reorder(created_at: :desc, id: :desc).limit(20).reverse
  end
end
