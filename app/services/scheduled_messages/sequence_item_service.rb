class ScheduledMessages::SequenceItemService
  def initialize(scheduled_message, position)
    @scheduled_message = scheduled_message
    @position = position
  end

  def perform
    @scheduled_message.with_lock do
      next unless @scheduled_message.sending?

      item = @scheduled_message.items.find_by!(position: @position)
      next unless item.pending?

      item.dispatching!
      message = Messages::MessageBuilder.new(
        @scheduled_message.sender,
        @scheduled_message.target_conversation,
        message_params(item)
      ).perform
      item.update!(message: message, dispatched_at: Time.current)
      @scheduled_message.update!(message: message) if @position.zero?
    end
  rescue StandardError => e
    mark_failed(e)
    raise
  end

  private

  def message_params(item)
    {
      content: item.content,
      content_type: item.content_type,
      content_attributes: item.content_attributes,
      attachments: item.signed_attachment_ids,
      is_voice_message: item.voice_message,
      message_type: 'outgoing',
      action: 'create'
    }
  end

  def mark_failed(error)
    item = @scheduled_message.items.find_by(position: @position)
    item&.update!(status: :failed, error_message: error.message)
    @scheduled_message.update!(status: :failed, error_message: error.message)
  end
end
