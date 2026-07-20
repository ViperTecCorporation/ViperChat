class ScheduledMessages::DeliveryStatusService
  INTERVAL = 10.seconds

  def initialize(message)
    @message = message
    @item = ScheduledMessageItem.find_by(message_id: message.id)
  end

  def sent
    return unless @item

    next_position = @item.with_lock { process_sent_item }
    ScheduledMessages::SequenceItemJob.set(wait: INTERVAL).perform_later(@item.scheduled_message_id, next_position) if next_position
  end

  def failed(error)
    return unless @item

    @item.with_lock { fail_schedule(error.message) }
  end

  private

  def process_sent_item
    schedule = @item.scheduled_message
    return unless schedule.sending? && @item.dispatching?

    return fail_schedule(@message.external_error.presence || 'Provider rejected the message') if @message.failed?

    @item.update!(status: :sent, sent_at: Time.current, error_message: nil)
    next_item = schedule.items.pending.where('position > ?', @item.position).first
    return next_item.position if next_item

    complete_schedule(schedule)
    nil
  end

  def complete_schedule(schedule)
    schedule.target_conversation.add_labels([schedule.label.title])
    schedule.update!(status: :sent, sent_at: Time.current, error_message: nil)
  end

  def fail_schedule(error_message)
    @item.update!(status: :failed, error_message: error_message)
    @item.scheduled_message.update!(status: :failed, error_message: error_message)
  end
end
