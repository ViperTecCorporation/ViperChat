class Voip::ProcessProviderEventJob < ApplicationJob
  queue_as :low

  def perform(event_id)
    event = VoipProviderEvent.find_by(id: event_id)
    return unless event
    return unless due?(event) && configured?(event)

    Voip::ReconcileProviderEventService.new(event: event).perform
    event.update!(last_error_code: nil, next_attempt_at: nil)
  rescue StandardError
    raise unless event&.persisted?

    record_failure(event)
  end

  private

  def due?(event)
    !event.processed_at && event.attempts < 8 && !event.next_attempt_at&.future?
  end

  def configured?(event)
    service = event.voip_service
    service.enabled? && %w[webhook viperconnect].include?(service.integration_provider) &&
      service.credentials['webhook_source_instance_id'] == event.source_instance_id
  end

  def record_failure(event)
    event.with_lock do
      next if event.processed_at

      attempts = event.attempts + 1
      event.update!(attempts: attempts, last_error_code: 'processing_failed',
                    next_attempt_at: attempts < 8 ? [30 * (2**attempts), 3600].min.seconds.from_now : nil)
    end
  end
end
