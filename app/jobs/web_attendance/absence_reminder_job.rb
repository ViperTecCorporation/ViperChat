class WebAttendance::AbsenceReminderJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, cycle, epoch)
    conversation = Conversation.find_by(id: conversation_id)
    WebAttendance::AbsenceReminderService.new(conversation).perform!(cycle, epoch) if conversation
  end
end
