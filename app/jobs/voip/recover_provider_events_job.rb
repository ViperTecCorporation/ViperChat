class Voip::RecoverProviderEventsJob < ApplicationJob
  queue_as :low

  def perform
    VoipProviderEvent.due.order(:created_at).limit(500).pluck(:id).each do |id|
      Voip::ProcessProviderEventJob.perform_later(id)
    end
    VoipCallArtifact.due.order(:updated_at).limit(100).pluck(:id).each { |id| Voip::PublishCallArtifactJob.perform_later(id) }
  end
end
