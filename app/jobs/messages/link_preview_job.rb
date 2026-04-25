class Messages::LinkPreviewJob < ApplicationJob
  queue_as :low

  def perform(message_id)
    message = Message.find_by(id: message_id)
    Messages::LinkPreviewService.new(message).perform if message.present?
  end
end
