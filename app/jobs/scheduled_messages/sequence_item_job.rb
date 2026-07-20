class ScheduledMessages::SequenceItemJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(scheduled_message_id, position)
    scheduled_message = ScheduledMessage.find(scheduled_message_id)
    ScheduledMessages::SequenceItemService.new(scheduled_message, position).perform
  end
end
