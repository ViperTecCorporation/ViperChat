class ProcessContactRemindersJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ContactReminder.pending.due.find_each(batch_size: 100) do |reminder|
      process_reminder(reminder)
    end
  end

  private

  def process_reminder(reminder)
    if reminder.conversation.present?
      if reminder.send_message? && reminder.message_content.present?
        # Action 2: Send message to client
        message = reminder.conversation.messages.build(
          content: reminder.message_content,
          account_id: reminder.account_id,
          inbox_id: reminder.conversation.inbox_id,
          message_type: :outgoing,
          sender: reminder.user || reminder.conversation.assignee
        )
        message.save!
      elsif reminder.user.present?
        # Action 1: Create a private note and mention the user to send an alert
        content = "@#{reminder.user.name} ⏰ **Lembrete de Agendamento:** #{reminder.message_content || 'Tarefa agendada venceu.'}"
        message = reminder.conversation.messages.build(
          content: content,
          account_id: reminder.account_id,
          inbox_id: reminder.conversation.inbox_id,
          message_type: :outgoing,
          private: true,
          sender: reminder.user
        )
        message.save!

        # Process the mention to generate system notification
        Messages::MentionService.new(message: message).perform
      end
    end

    reminder.update!(is_completed: true)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: reminder.account).capture_exception
  end
end
