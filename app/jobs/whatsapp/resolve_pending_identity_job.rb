class Whatsapp::ResolvePendingIdentityJob < ApplicationJob
  queue_as :low

  def perform(id = nil)
    if id
      resolution = WhatsappIdentityResolution.find_by(id: id)
      Whatsapp::PendingIdentityResolutionService.new(resolution: resolution).perform if resolution
    else
      # The persisted due date is the recovery mechanism if an enqueue is lost.
      WhatsappIdentityResolution.due.order(:next_attempt_at).limit(100).pluck(:id).each do |resolution_id|
        self.class.perform_later(resolution_id)
      end
    end
  end
end
