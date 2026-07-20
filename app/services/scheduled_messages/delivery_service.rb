class ScheduledMessages::DeliveryService
  def initialize(scheduled_message)
    @scheduled_message = scheduled_message
  end

  def perform
    claimed = false
    @scheduled_message.with_lock do
      next unless @scheduled_message.scheduled?

      claimed = true
      @scheduled_message.sending!
      @scheduled_message.ensure_legacy_item!
      conversation = target_conversation
      conversation.update!(assignee: @scheduled_message.sender)
      conversation.conversation_participants.find_or_create_by!(user: @scheduled_message.sender)
      @scheduled_message.update!(target_conversation: conversation, error_message: nil)
    end
    ScheduledMessages::SequenceItemJob.perform_later(@scheduled_message.id, 0) if claimed
  rescue StandardError => e
    mark_failed(e)
    raise
  end

  private

  def target_conversation
    current = @scheduled_message.contact.conversations.where(inbox: @scheduled_message.inbox).order(created_at: :desc).first
    return create_conversation if current.nil?
    return current unless current.resolved? || current.snoozed?
    return current.tap(&:open!) if @scheduled_message.inbox.lock_to_single_conversation?

    create_conversation
  end

  def create_conversation
    contact_inbox = @scheduled_message.contact.contact_inboxes.find_by!(inbox: @scheduled_message.inbox)
    Conversation.create!(
      account: @scheduled_message.account, inbox: @scheduled_message.inbox, contact: @scheduled_message.contact,
      contact_inbox: contact_inbox, assignee: @scheduled_message.sender
    )
  end

  def mark_failed(error)
    @scheduled_message.update!(status: :failed, error_message: error.message)
  end
end
