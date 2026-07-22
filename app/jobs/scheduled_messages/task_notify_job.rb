class ScheduledMessages::TaskNotifyJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ScheduledMessage.due_tasks.find_each do |scheduled_message|
      notify_assignee(scheduled_message)
    rescue StandardError => e
      Rails.logger.error("[ScheduledMessages::TaskNotifyJob] id=#{scheduled_message.id} failed: #{e.message}")
    end
  end

  private

  def notify_assignee(scheduled_message)
    notification = Notification.create!(
      account: scheduled_message.account,
      user: scheduled_message.created_by,
      notification_type: :scheduled_task_due,
      primary_actor: scheduled_message.conversation,
      secondary_actor: scheduled_message,
      meta: {
        scheduled_message_id: scheduled_message.id,
        reason: scheduled_message.reason,
        scheduled_at: scheduled_message.scheduled_at
      }
    )
    scheduled_message.cancelled!
    notification
  end
end
