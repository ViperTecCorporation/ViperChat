# Mail delivery adapter: reuse the existing MIME builder, attachments and reply headers.
class Google::GmailDelivery
  attr_accessor :settings

  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    channel = Channel::Email.find(settings.fetch(:channel_id))
    raise 'Gmail API is not enabled for this inbox' unless channel.gmail_api?

    raw = mail.encoded
    # Mail hides Bcc when encoding for SMTP (which uses the envelope instead).
    # Gmail API needs these recipients in the uploaded MIME message.
    raw = "Bcc: #{mail.bcc.join(', ')}\r\n#{raw}" if mail.bcc.present? && !raw.match?(/^Bcc:/i)
    Google::GmailClient.new(channel: channel).send_message(raw, thread_id: settings[:thread_id])
  end
end
