class Whatsapp::ProcessUnifiedEventJob < ApplicationJob
  queue_as :low

  def perform(event_id = nil)
    if event_id
      event = WhatsappUnifiedEvent.find_by(id: event_id)
      Whatsapp::UnifiedEventService.new(event: event).perform if event
    else
      WhatsappUnifiedEvent.where(state: 'pending').where('next_attempt_at <= ?', Time.current)
                          .find_each { |event| self.class.perform_later(event.id) }
    end
  end
end
