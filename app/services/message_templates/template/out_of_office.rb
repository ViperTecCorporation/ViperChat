class MessageTemplates::Template::OutOfOffice
  pattr_initialize [:conversation!]

  def self.perform_if_applicable(conversation)
    inbox = conversation.inbox
    return unless inbox.out_of_office?
    return if inbox.out_of_office_message.blank?
    return if skip_group_conversation?(conversation)

    new(conversation: conversation).perform
  end

  def perform
    return if self.class.skip_group_conversation?(conversation)

    ActiveRecord::Base.transaction do
      conversation.messages.create!(out_of_office_message_params)
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    true
  end

  def self.skip_group_conversation?(conversation)
    conversation.group? && !conversation.inbox.out_of_office_send_to_groups?
  end

  private

  delegate :contact, :account, to: :conversation
  delegate :inbox, to: :message

  def out_of_office_message_params
    content = @conversation.inbox&.out_of_office_message

    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :template,
      content: content
    }
  end
end
