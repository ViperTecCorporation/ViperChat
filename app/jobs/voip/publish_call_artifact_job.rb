class Voip::PublishCallArtifactJob < ApplicationJob
  queue_as :low

  def perform(id)
    artifact = VoipCallArtifact.find_by(id: id)
    Voip::PublishCallArtifactService.new(artifact: artifact).perform if artifact
  end
end
