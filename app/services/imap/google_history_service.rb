require 'timeout'

# One bounded batch per scheduled inbox poll, under the same inbox mutex as live mail.
class Imap::GoogleHistoryService < Imap::GoogleFetchEmailService
  BATCH_SIZE = 50

  def perform
    @history = channel.reload.provider_config.to_h[Google::EmailHistory::KEY]
    return unless @history && @history['status'] == 'running'

    Timeout.timeout(60) { import_batch }
  rescue StandardError => e
    Google::EmailHistory.update!(channel, @history['id'], 'status' => 'failed', 'error' => e.class.name) if @history
    Rails.logger.warn("Gmail history failed for inbox #{channel.inbox.id}: #{e.class.name}")
  ensure
    disconnect_history_client
  end

  private

  def disconnect_history_client
    @imap_client&.disconnect unless @imap_client&.disconnected?
  end

  def import_batch
    day = Date.iso8601(@history.fetch('day'))
    batch = batch_uids(day)
    return unless batch.all? { |uid| process_uid(uid) }
    return if batch.length == BATCH_SIZE

    previous = day - 1
    status = previous < Time.iso8601(@history.fetch('since')).to_date ? 'completed' : 'running'
    Google::EmailHistory.update!(channel, @history['id'], 'day' => previous.iso8601, 'uid' => 0, 'status' => status)
  end

  def batch_uids(day)
    # UID search is bounded to one day; the UID cursor survives batch retries.
    uids = imap_client.uid_search(['SINCE', day.strftime('%d-%b-%Y'), 'BEFORE', (day + 1).strftime('%d-%b-%Y')])
    @validity = imap_client.responses['UIDVALIDITY'].last
    cursor = @history['uidvalidity'] == @validity ? @history['uid'].to_i : 0
    uids.select { |uid| uid > cursor }.sort.first(BATCH_SIZE)
  end

  def process_uid(uid)
    current = channel.reload.provider_config[Google::EmailHistory::KEY]
    return false unless current && current['status'] == 'running' && current['id'] == @history['id']

    fetch_and_process(uid)
    @history['processed'] += 1
    checkpoint = { 'uid' => uid, 'uidvalidity' => @validity, 'processed' => @history['processed'] }
    Google::EmailHistory.update!(channel, @history['id'], checkpoint)
  end

  def fetch_and_process(uid)
    data = imap_client.uid_fetch(uid, ['INTERNALDATE', 'BODY.PEEK[]'])&.first
    return unless data # Message removed from INBOX during the import.

    return unless within_history?(data)

    mail = build_mail_from_string(data.attr.fetch('BODY[]'))
    mail.message_id = "imap-uid:#{uid}" if mail.message_id.blank?
    return if email_already_present?(channel, mail.message_id)
    return if MailPresenter.new(mail, channel.account).notification_email_from_chatwoot?

    Imap::ImapMailbox.new.process(mail, channel)
  end

  def within_history?(data)
    date = data.attr.fetch('INTERNALDATE').to_time
    date.between?(Time.iso8601(@history.fetch('since')), Time.iso8601(@history.fetch('until')))
  end
end
