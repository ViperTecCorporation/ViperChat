class CsatSurveyListener < BaseListener
  def conversation_status_changed(event)
    return if event.data[:web_attendance]

    conversation = extract_conversation_and_account(event)[0]

    return unless conversation.resolved?

    CsatSurveyService.new(conversation: conversation).perform
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return if event.data[:web_attendance] || message.web_attendance?
    return unless message.input_csat?

    CsatSurveys::ResponseBuilder.new(message: message).perform
  end
end
