class Whatsapp::Unoapi::ContactSync::PageJob < MutexApplicationJob
  queue_as :low

  GLOBAL_LOCK = 'unoapi-contact-sync:global-page'.freeze
  LOCK_TIMEOUT = 15.minutes
  MAX_RETRIES = 3
  NEXT_PAGE_DELAY = 2.seconds

  retry_on_lock_conflict wait: 30.seconds, attempts: 20

  def perform(channel_id, cursor, retry_count = 0)
    with_lock(GLOBAL_LOCK, LOCK_TIMEOUT) do
      channel = Channel::Whatsapp.find_by(id: channel_id)
      next unless runnable?(channel, cursor)

      process_page(channel, cursor, retry_count)
    end
  end

  private

  def runnable?(channel, cursor)
    channel&.provider == 'unoapi' &&
      channel.contact_sync_enabled? &&
      channel.contact_sync_cursor == cursor &&
      %w[scheduled running].include?(channel.contact_sync_status)
  end

  def process_page(channel, cursor, retry_count)
    client = Whatsapp::Unoapi::ContactSync::Client.new(channel)
    return wait_for_connection(channel) if cursor == '0' && !client.session_online?

    mark_running(channel)
    page = client.contacts(cursor: cursor)
    validate_page!(page, cursor)
    processed, failed = import_contacts(channel, page.fetch('contacts'), client)
    finish_page(channel, page, cursor, processed, failed)
  rescue Whatsapp::Unoapi::ContactSync::Client::ProviderMismatchError => e
    mark_paused(channel, e.message)
  rescue Whatsapp::Unoapi::ContactSync::Client::TransientError => e
    retry_page(channel, cursor, retry_count, e)
  rescue Whatsapp::Unoapi::ContactSync::Client::PermanentError, KeyError, ArgumentError => e
    mark_failed(channel, e.message)
  end

  def mark_running(channel)
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      contact_sync_status: 'running',
      contact_sync_started_at: channel.contact_sync_started_at || Time.current,
      contact_sync_error: nil,
      contact_sync_next_run_at: nil
    )
  end

  def import_contacts(channel, contacts, client)
    processed = 0
    failed = 0
    importers = Whatsapp::Unoapi::ContactSync::ContactImporter.build_for_page(
      channel: channel,
      payloads: contacts,
      client: client
    )
    contacts.zip(importers).each do |payload, importer|
      result = importer.perform
      processed += 1 if %i[processed skipped].include?(result)
    rescue StandardError => e
      failed += 1
      Rails.logger.error(
        "[UNOAPI CONTACT SYNC] channel_id=#{channel.id} user_id=#{payload['user_id']} " \
        "phone=#{payload['phone_number']} error=#{e.class}: #{e.message}"
      )
    end
    [processed, failed]
  end

  def finish_page(channel, page, cursor, processed, failed)
    next_cursor = page['next_cursor'].to_s
    has_more = ActiveModel::Type::Boolean.new.cast(page['has_more'])
    accumulated_failed = channel.contact_sync_failed_count + failed
    attributes = {
      contact_sync_processed_count: channel.contact_sync_processed_count + processed,
      contact_sync_failed_count: accumulated_failed,
      contact_sync_total_count: page['total_count'].to_i
    }

    return schedule_next_page(channel, attributes, cursor, next_cursor) if has_more

    complete_sync(channel, attributes, accumulated_failed)
  end

  def schedule_next_page(channel, attributes, cursor, next_cursor)
    raise ArgumentError, 'UnoAPI returned an empty or repeated next_cursor' if next_cursor.blank? || next_cursor == cursor

    channel.update_columns(attributes.merge( # rubocop:disable Rails/SkipsModelValidations
                             contact_sync_status: 'scheduled',
                             contact_sync_cursor: next_cursor,
                             contact_sync_next_run_at: Time.current + NEXT_PAGE_DELAY
                           ))
    self.class.set(wait: NEXT_PAGE_DELAY).perform_later(channel.id, next_cursor)
  end

  def complete_sync(channel, attributes, accumulated_failed)
    attributes[:contact_sync_total_count] = attributes[:contact_sync_processed_count] + accumulated_failed
    channel.update_columns(attributes.merge( # rubocop:disable Rails/SkipsModelValidations
                             contact_sync_status: 'completed',
                             contact_sync_cursor: nil,
                             contact_sync_completed_at: Time.current,
                             contact_sync_next_run_at: 3.hours.from_now,
                             contact_sync_error: accumulated_failed.positive? ? "#{accumulated_failed} contact(s) failed" : nil
                           ))
    Whatsapp::Unoapi::ContactSync::ExportJob.perform_later(channel.id) if channel.contact_export_enabled?
  end

  def validate_page!(page, cursor)
    raise ArgumentError, "UnoAPI contacts page #{cursor} is not an object" unless page.is_a?(Hash)
    raise ArgumentError, "UnoAPI contacts page #{cursor} has no contacts array" unless page['contacts'].is_a?(Array)
  end

  def wait_for_connection(channel)
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      contact_sync_status: 'waiting_connection',
      contact_sync_next_run_at: 1.minute.from_now
    )
    Whatsapp::Unoapi::ContactSync::ConnectionCheckJob.set(wait: 1.minute).perform_later(channel.id, 1)
  end

  def retry_page(channel, cursor, retry_count, error)
    return mark_failed(channel, error.message) if retry_count >= MAX_RETRIES

    delay = (2**retry_count).minutes
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      contact_sync_status: 'scheduled',
      contact_sync_error: error.message,
      contact_sync_next_run_at: Time.current + delay
    )
    self.class.set(wait: delay).perform_later(channel.id, cursor, retry_count + 1)
  end

  def mark_paused(channel, error)
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      contact_sync_status: 'paused',
      contact_sync_error: error,
      contact_sync_next_run_at: nil
    )
  end

  def mark_failed(channel, error)
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      contact_sync_status: 'failed',
      contact_sync_error: error,
      contact_sync_next_run_at: nil
    )
  end
end
