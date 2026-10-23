class Voip::SyncHistoryJob < ApplicationJob
  queue_as :low

  def perform(service_id)
    service = VoipService.find_by(id: service_id)
    Voip::SyncHistoryService.new(service: service).perform if service
  end
end
