# A bounded, durable scan. Keep both date bounds fixed while paging so a busy
# inbox cannot starve older pages. Only move the watermark after ingestion succeeds.
class Google::GmailSyncService
  pattr_initialize [:channel!, :interval]

  def perform
    Timeout.timeout(120) { sync_page }
  end

  private

  def sync_page
    state = scan_state
    save_state(state)
    client = Google::GmailClient.new(channel: channel)
    query = "in:inbox after:#{lower_bound(state)} before:#{Time.parse(state['until']).to_i + 1}"
    page = client.list_messages(query: query, page_token: state['page_token'])
    page.fetch('messages', []).reverse_each do |message|
      Google::GmailMessageService.new(channel: channel, client: client).perform(message.fetch('id'))
    end
    save_state(next_state(state, page))
  end

  def lower_bound(state)
    lower = Time.parse(state['since']).to_i - 60
    cutoff = channel.provider_config['receive_since']
    cutoff.present? ? [lower, Time.parse(cutoff).to_i].max : lower
  end

  def scan_state
    channel.reload
    state = channel.provider_config['gmail_sync'] || {}
    from = state['since'] || channel.provider_config['receive_since'] || (Time.current - (interval || 1).to_i.days).iso8601
    until_time = state['until'] || Time.current.utc.iso8601
    state.merge('since' => from, 'until' => until_time)
  end

  def next_state(state, page)
    return state.merge('page_token' => page['nextPageToken']) if page['nextPageToken'].present?

    { 'since' => state['until'] }
  end

  def save_state(state)
    channel.with_lock do
      channel.update!(provider_config: channel.provider_config.to_h.merge('gmail_sync' => state))
    end
  end
end
