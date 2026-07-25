class Whatsapp::Unoapi::ContactSync::ConnectionCheckJob < ApplicationJob
  queue_as :low

  RETRY_INTERVAL = 1.minute
  MAX_ATTEMPTS = 30
  FIRST_SYNC_DELAY = 3.minutes

  def perform(channel_id, attempt = 0)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return unless eligible?(channel)
    return if sync_in_progress?(channel)

    if Whatsapp::Unoapi::ContactSync::Client.new(channel).session_online?
      schedule_sync(channel)
    else
      retry_connection(channel, attempt)
    end
  rescue Whatsapp::Unoapi::ContactSync::Client::TransientError => e
    retry_connection(channel, attempt, e.message)
  rescue Whatsapp::Unoapi::ContactSync::Client::PermanentError => e
    mark_failed(channel, e.message)
  end

  private

  def eligible?(channel)
    channel&.provider == 'unoapi' && channel.contact_sync_enabled?
  end

  def sync_in_progress?(channel)
    %w[scheduled running].include?(channel.contact_sync_status) && channel.contact_sync_cursor.present?
  end

  def schedule_sync(channel)
    delay = channel.contact_sync_completed_at.present? ? 0.seconds : FIRST_SYNC_DELAY
    run_at = Time.current + delay
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      contact_sync_status: 'scheduled',
      contact_sync_cursor: '0',
      contact_sync_processed_count: 0,
      contact_sync_failed_count: 0,
      contact_sync_total_count: nil,
      contact_sync_error: nil,
      contact_sync_started_at: nil,
      contact_sync_next_run_at: run_at
    )
    Whatsapp::Unoapi::ContactSync::PageJob.set(wait: delay).perform_later(channel.id, '0')
  end

  def retry_connection(channel, attempt, error = nil)
    return mark_failed(channel, error || 'UnoAPI session did not become online within 30 minutes') if attempt >= MAX_ATTEMPTS

    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      contact_sync_status: 'waiting_connection',
      contact_sync_error: error,
      contact_sync_next_run_at: Time.current + RETRY_INTERVAL
    )
    self.class.set(wait: RETRY_INTERVAL).perform_later(channel.id, attempt + 1)
  end

  def mark_failed(channel, error)
    channel&.update_columns( # rubocop:disable Rails/SkipsModelValidations
      contact_sync_status: 'failed',
      contact_sync_error: error,
      contact_sync_next_run_at: nil
    )
  end
end
