# Retry retained webhook evidence, never uncertain outbound deliveries. The normal
# ingestion path still decides whether correlation is safe and owns deduplication.
class Whatsapp::RecheckUnifiedEventsJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 100
  INTERVAL = 5.minutes

  def perform
    WhatsappUnifiedEvent.joins(:whatsapp_inbox_link)
                        .where(state: 'review', whatsapp_inbox_links: { enabled: true })
                        .where('whatsapp_unified_events.activation_cutoff = whatsapp_inbox_links.activated_at')
                        .where('whatsapp_unified_events.updated_at <= ?', INTERVAL.ago)
                        .where.not(payload: {})
                        .order(:updated_at, :id).limit(BATCH_SIZE).each { |event| recheck(event) }
    # Contact/receipt evidence can improve after the media job's short retries
    # have finished. Reuse the same proof checks; never force a success status.
    WhatsappUnifiedMessage.where(media_review_status: %w[pending review]).where.not(message_id: nil)
                          .where(whatsapp_inbox_link_id: WhatsappInboxLink.active.select(:id))
                          .where('updated_at <= ?', INTERVAL.ago).order(:updated_at, :id).limit(BATCH_SIZE)
                          .each { |record| Whatsapp::ReconcileUnifiedMediaJob.perform_later(record.id) }
  end

  private

  def recheck(event)
    event.with_lock do
      link = event.whatsapp_inbox_link.reload
      next unless event.state == 'review' && event.updated_at <= INTERVAL.ago && event.payload.present?
      next unless link.enabled? && link.activated_at == event.activation_cutoff

      event.update!(state: 'pending', next_attempt_at: Time.current)
      Whatsapp::ProcessUnifiedEventJob.perform_later(event.id)
    end
  rescue StandardError => e
    Rails.logger.warn({ event: 'whatsapp_unified_event_recheck_failed', event_id: event.id, error_class: e.class.name }.to_json)
  end
end
