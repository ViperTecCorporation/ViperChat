class Google::GmailHistoryService
  pattr_initialize [:channel!]

  def perform
    history = channel.reload.provider_config[Google::EmailHistory::KEY]
    return unless history && history['status'] == 'running'

    Timeout.timeout(60) { import_page(history) }
  rescue StandardError => e
    Google::EmailHistory.update!(channel, history['id'], { 'status' => 'failed', 'error' => e.class.name }) if history
    raise
  end

  private

  def import_page(history)
    client = Google::GmailClient.new(channel: channel)
    query = "in:inbox after:#{Time.parse(history.fetch('since')).to_i} before:#{Time.parse(history.fetch('until')).to_i + 1}"
    page = client.list_messages(query: query, page_token: history['gmail_page_token'])
    return unless process_messages(page, history, client)

    save_checkpoint(page, history)
  end

  def process_messages(page, history, client)
    page.fetch('messages', []).reverse.all? do |message|
      current = channel.reload.provider_config[Google::EmailHistory::KEY]
      next false unless current && current['status'] == 'running' && current['id'] == history['id']

      Google::GmailMessageService.new(channel: channel, client: client).perform(message.fetch('id'))
      true
    end
  end

  def save_checkpoint(page, history)
    checkpoint = {
      'gmail_page_token' => page['nextPageToken'],
      'processed' => history['processed'].to_i + page.fetch('messages', []).size,
      'status' => page['nextPageToken'].present? ? 'running' : 'completed'
    }
    Google::EmailHistory.update!(channel, history['id'], checkpoint)
  end
end
