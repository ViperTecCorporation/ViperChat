class MessageTemplates::Template::Greeting
  pattr_initialize [:conversation!]

  def perform
    if @conversation.inbox.web_attendance_available? && @conversation.inbox.web_attendance_greeting_enabled?
      return WebAttendance::InvitationService.new(conversation: @conversation).create!(
        content: @conversation.inbox.greeting_message, request_id: "greeting-#{@conversation.web_attendance_cycle}", greeting: true
      )
    end

    ActiveRecord::Base.transaction do
      conversation.messages.create!(greeting_message_params)
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    true
  end

  private

  delegate :contact, :account, to: :conversation
  delegate :inbox, to: :message

  def greeting_message_params
    content = @conversation.inbox&.greeting_message

    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :template,
      content: content
    }
  end
end
