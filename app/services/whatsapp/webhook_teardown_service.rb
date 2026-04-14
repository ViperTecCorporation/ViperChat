class Whatsapp::WebhookTeardownService
  def initialize(channel)
    @channel = channel
  end

  def perform
    Rails.logger.info "[WHATSAPP] Skipping WABA webhook unsubscribe for channel #{@channel.id}"
  end
end
