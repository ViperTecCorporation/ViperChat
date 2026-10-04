class WebAttendance::DeliveryReceiptService
  def initialize(conversation:, messages:, message_type:)
    @conversation = conversation
    @messages = messages
    @message_type = message_type
  end

  def perform
    return unless @messages.any? { |message| pending_receipt?(message) }

    @conversation.with_lock do
      next if @conversation.resolved? || !@conversation.inbox.web_attendance_available?

      Current.with_web_attendance(@conversation) do
        @messages.each { |message| acknowledge(message) }
      end
    end
  end

  private

  def pending_receipt?(message)
    message.web_attendance? && message.message_type == @message_type && message.sent?
  end

  def acknowledge(message)
    return unless message.conversation_id == @conversation.id && message.web_attendance? && !message.private?
    return unless message.message_type == @message_type && current_cycle?(message)

    message.with_lock do
      message.update!(status: :delivered) if message.sent?
    end
  end

  def current_cycle?(message)
    boundary = @conversation.web_attendance_start_message_id
    return message.id >= boundary if boundary

    message.created_at >= @conversation.web_attendance_started_at
  end
end
