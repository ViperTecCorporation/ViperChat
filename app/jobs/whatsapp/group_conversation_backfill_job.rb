class Whatsapp::GroupConversationBackfillJob < ApplicationJob
  queue_as :low

  def perform(inbox_id)
    inbox = Inbox.find_by(id: inbox_id)
    return if inbox.blank?

    stats = Whatsapp::GroupConversationBackfillService.new(inbox: inbox).perform
    Rails.logger.info(
      "[WHATSAPP][GROUP] backfill completed inbox_id=#{inbox.id} conversations=#{stats[:conversations]} members=#{stats[:members]}"
    )
  end
end
