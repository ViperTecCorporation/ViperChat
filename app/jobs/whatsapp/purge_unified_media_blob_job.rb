class Whatsapp::PurgeUnifiedMediaBlobJob < ApplicationJob
  queue_as :purgable

  def perform(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    Whatsapp::UnifiedMediaBlobPurgeService.new(blob: blob).perform if blob
  end
end
