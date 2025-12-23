class Conversations::AttachmentsBulkDeleteJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 500

  def perform(conversation, attachment_ids: [], delete_all: false)
    attachments = conversation.attachments
    attachments = attachments.where(id: attachment_ids) unless delete_all
    attachments = attachments.reorder(nil)

    total_count = attachments.count
    return if total_count.zero?

    message_ids = attachments.distinct.pluck(:message_id)

    attachments.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each do |attachment|
        attachment.file.purge_later if attachment.file.attached?
        attachment.destroy!
      end
    end

    Message.where(id: message_ids).find_each do |message|
      if message.attachments.exists?
        message.update!(updated_at: Time.zone.now)
        next
      end

      if message.content.blank?
        message.update!(
          content: I18n.t('conversations.messages.deleted'),
          content_type: :text,
          content_attributes: { deleted: true }
        )
      else
        message.update!(updated_at: Time.zone.now)
      end
    end

    Conversations::ActivityMessageJob.perform_later(
      conversation,
      {
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        message_type: :activity,
        content: I18n.t('conversations.activity.attachments.deleted', count: total_count),
        private: true
      }
    )
  end
end
