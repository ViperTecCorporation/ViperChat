class Uploads::CleanupMultipartJob < ApplicationJob
  queue_as :purgable
  retry_on StandardError, wait: 1.hour, attempts: 5

  def perform(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob&.metadata&.key?('multipart')

    Uploads::MultipartService.new(blob).abort!
  end
end
