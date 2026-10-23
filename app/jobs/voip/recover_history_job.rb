class Voip::RecoverHistoryJob < ApplicationJob
  queue_as :low

  def perform
    VoipService.where(enabled: true).find_each do |service|
      next unless service.integration_provider == 'viperconnect'

      Voip::SyncHistoryJob.perform_later(service.id)
    end
  end
end
