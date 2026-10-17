# Recheck at deletion time too: references can be added after reconciliation
# committed and before the purge job runs. Never delegate that race to AS alone.
class Whatsapp::UnifiedMediaBlobPurgeService
  def self.unreferenced?(blob)
    !blob.attachments.exists? && !ActiveStorage::VariantRecord.exists?(blob_id: blob.id) &&
      !WhatsappSticker.exists?(blob_id: blob.id) && !scheduled_reference?(blob)
  end

  def self.scheduled_reference?(blob)
    [ScheduledMessage, ScheduledMessageItem].any? do |model|
      model.where.not(attachment_blob_ids: []).pluck(:attachment_blob_ids).flatten.any? do |reference|
        reference.to_s == blob.id.to_s || ActiveStorage::Blob.find_signed(reference.to_s)&.id == blob.id
      end
    end
  end

  def initialize(blob:)
    @blob = blob
  end

  def perform
    @blob.with_lock { @blob.purge if self.class.unreferenced?(@blob) }
  end
end
