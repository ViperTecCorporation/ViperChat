require 'stringio'

class Messages::ForwardService
  pattr_initialize [:account!, :user!, :source_messages!, :target_contact_inbox!]

  def perform
    ActiveRecord::Base.transaction do
      @conversation = build_conversation
      forward_messages
    end

    @conversation
  end

  private

  def build_conversation
    conversation = existing_conversation

    if conversation
      reopen_and_assign_conversation(conversation)
      conversation
    else
      Conversation.create!(
        account: account,
        inbox: target_contact_inbox.inbox,
        contact: target_contact_inbox.contact,
        contact_inbox: target_contact_inbox,
        status: :open,
        assignee: user
      )
    end
  end

  def existing_conversation
    if target_contact_inbox.inbox.lock_to_single_conversation
      target_contact_inbox.conversations.order(:created_at).last
    else
      target_contact_inbox.conversations.open.order(:created_at).last
    end
  end

  def reopen_and_assign_conversation(conversation)
    conversation.status = :open unless conversation.open?
    conversation.assignee = user
    conversation.save!
  end

  def forward_messages
    source_messages.each do |original_message|
      new_message = build_forwarded_message(original_message)
      duplicate_attachments(original_message, new_message)
      new_message.save!
    end
  end

  def build_forwarded_message(original_message)
    Message.new(
      account: account,
      inbox: target_contact_inbox.inbox,
      conversation: @conversation,
      message_type: :outgoing,
      content: original_message.outgoing_content,
      content_type: original_message.content_type,
      sender: user,
      private: false,
      content_attributes: forward_content_attributes(original_message)
    )
  end

  def forward_content_attributes(original_message)
    original_message.content_attributes.to_h.merge(
      forwarded_from_conversation_id: original_message.conversation_id,
      forwarded_from_message_id: original_message.id
    )
  end

  def duplicate_attachments(original_message, new_message)
    original_message.attachments.each do |attachment|
      next unless attachment.file.attached?

      new_attachment = new_message.attachments.build(
        account_id: attachment.account_id,
        file_type: attachment.file_type,
        extension: attachment.extension,
        external_url: attachment.external_url,
        fallback_title: attachment.fallback_title,
        meta: attachment.meta
      )

      new_attachment.file.attach(
        io: StringIO.new(attachment.file.download),
        filename: attachment.file.filename.to_s,
        content_type: attachment.file.content_type
      )
    end
  end
end

Messages::ForwardService.prepend_mod_with('Messages::ForwardService')
