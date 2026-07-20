class ScheduledMessages::DeliveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ScheduledMessage.due.find_each do |scheduled_message|
      ScheduledMessages::DeliveryService.new(scheduled_message).perform
    rescue StandardError => e
      Rails.logger.error("[ScheduledMessages] id=#{scheduled_message.id} failed: #{e.message}")
    end
  end
end
