class Google::SyncSentMessageJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 10

  def perform(message)
    channel = message.inbox.channel
    return unless channel.is_a?(Channel::Email) && channel.gmail_api?

    id = message.external_source_ids.to_h.fetch('gmail_message_id')
    data = Google::GmailClient.new(channel: channel).message_metadata(id)
    header = data.fetch('payload').fetch('headers').find { |entry| entry['name'].casecmp?('Message-ID') }
    raise 'Gmail sent message has no Message-ID yet' if header.nil? || header['value'].blank?

    message.update!(source_id: Mail::MessageIdField.new(header.fetch('value')).message_id)
  end
end
