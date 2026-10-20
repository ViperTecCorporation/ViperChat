class Whatsapp::ImportHistoryJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::Deadlocked, wait: 10.seconds, attempts: 5

  def perform(event_id = nil)
    scope = WhatsappManagementEvent.where(field: 'history', state: 'pending_import').where('expires_at > ?', Time.current)
    scope = scope.where(id: event_id) if event_id
    scope.order(:updated_at, :id).limit(100).each do |event|
      Whatsapp::HistoryImportService.new(event: event).perform
    rescue StandardError => e
      # Never log a provider body, signed URL, token or message content.
      Rails.logger.warn("[WHATSAPP][HISTORY] event_id=#{event.id} error_class=#{e.class.name}")
    ensure
      # Rotate unresolved batches; one ambiguous/reauth-required batch must not
      # permanently occupy the first page of every five-minute sweep.
      event.update!(updated_at: Time.current) if event.persisted? && event.state == 'pending_import'
    end
  end
end
