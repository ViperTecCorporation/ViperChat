class Google::GmailMessageService
  pattr_initialize [:channel!, :client!]

  def perform(id)
    data = client.message(id)
    mail = Mail.read_from_string(Base64.urlsafe_decode64(data.fetch('raw')))
    mail.message_id = "gmail-#{id}@gmail.local" if mail.message_id.blank?
    return if skip?(mail)

    Timeout.timeout(GlobalConfigService.load('EMAIL_PROCESSING_TIMEOUT_SECONDS', 60).to_i) do
      ingest(mail, data)
    end
  rescue CustomExceptions::GmailError => e
    raise unless e.status == 404 # Deleted from Gmail between list and get.
  end

  private

  def ingest(mail, data)
    ActiveRecord::Base.transaction do
      Google::GmailMailbox.new(thread_id: data['threadId']).process(mail, channel)
      message = channel.inbox.messages.find_by(source_id: mail.message_id)
      message&.update!(external_source_ids: message.external_source_ids.to_h.merge('gmail_thread_id' => data['threadId']))
    end
  end

  def skip?(mail)
    channel.inbox.messages.exists?(source_id: mail.message_id) ||
      Imap::DeletedMessageTracker.new(inbox: channel.inbox).deleted?(mail.message_id) ||
      MailPresenter.new(mail, channel.account).notification_email_from_chatwoot?
  end
end
