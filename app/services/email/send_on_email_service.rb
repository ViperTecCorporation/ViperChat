class Email::SendOnEmailService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Email
  end

  def perform_reply
    return unless message.email_notifiable_message?

    reply_mail = ConversationReplyMailer.with(account: message.account).email_reply(message).deliver_now
    Rails.logger.info("Email message #{message.id} sent with source_id: #{reply_mail.message_id}")
    message.update(source_id: reply_mail.message_id)
    synchronize_gmail_message(reply_mail)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: message.account).capture_exception
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end

  def synchronize_gmail_message(reply_mail)
    return unless channel.gmail_api?

    response = reply_mail.delivery_method.response
    message.update!(external_source_ids: message.external_source_ids.to_h.merge(
      'gmail_message_id' => response.fetch('id'), 'gmail_thread_id' => response.fetch('threadId')
    ))
    record_gmail_thread(response.fetch('threadId'))
    Google::SyncSentMessageJob.perform_now(message)
  rescue StandardError => e
    # Gmail has already accepted the message. Never mark it failed and invite a duplicate send.
    ChatwootExceptionTracker.new(e, account: message.account).capture_exception
  end

  def record_gmail_thread(thread_id)
    conversation.with_lock do
      conversation.update!(additional_attributes: conversation.additional_attributes.merge('gmail_thread_id' => thread_id))
    end
  end
end
