class Conversations::DeleteWithAttachmentsJob < ApplicationJob
  queue_as :low

  def perform(conversation, user = nil, ip = nil)
    purge_conversation_attachments(conversation)
    remove_scheduled_message_references(conversation)
    DeleteObjectJob.perform_now(conversation, user, ip)
  end

  private

  def purge_conversation_attachments(conversation)
    conversation.attachments.reorder(nil).find_each do |attachment|
      attachment.file.purge_later if attachment.file.attached?
      attachment.destroy!
    end
  end

  def remove_scheduled_message_references(conversation)
    ScheduledMessage.where(target_conversation_id: conversation.id).update_all(target_conversation_id: nil) # rubocop:disable Rails/SkipsModelValidations
    ScheduledMessage.where(conversation_id: conversation.id).find_each(&:destroy!)
  end
end
