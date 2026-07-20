class ScheduledMessages::DeliveryStatusJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(message_id)
    ScheduledMessages::DeliveryStatusService.new(Message.find(message_id)).sent
  end
end
