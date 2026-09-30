class Google::GmailMailbox < Imap::ImapMailbox
  def initialize(thread_id:)
    super()
    @gmail_thread_id = thread_id
  end

  private

  def find_conversation_by_in_reply_to
    super || find_conversation_by_gmail_thread
  end

  def find_conversation_by_gmail_thread
    return if @gmail_thread_id.blank?

    # Message-ID lookup can still be pending after a successful send.
    @inbox.conversations.find_by("additional_attributes->>'gmail_thread_id' = ?", @gmail_thread_id)
  end
end
