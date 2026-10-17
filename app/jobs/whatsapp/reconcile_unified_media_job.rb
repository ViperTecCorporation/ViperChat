class Whatsapp::ReconcileUnifiedMediaJob < ApplicationJob
  queue_as :low

  def perform(record_id, attempt = 0)
    record = WhatsappUnifiedMessage.find_by(id: record_id)
    return unless record&.message_id && Whatsapp::UnifiedMediaReconciliationService::MEDIA_TYPES.key?(record.message_kind)

    result = Whatsapp::UnifiedMediaReconciliationService.new(record: record).perform
    record.update!(media_review_status: result.status.to_s, media_review_reason: result.reason.to_s)
    Message.where(id: result.message_ids).find_each(&:send_update_event) if result.status == :reconciled
    self.class.set(wait: 30.seconds).perform_later(record.id, attempt + 1) if result.status == :pending && attempt < 5
    log_result(record, result)
  end

  private

  def log_result(record, result)
    Rails.logger.info({ event: 'whatsapp_unified_media_reconciliation', record_id: record.id,
                        status: result.status, reason: result.reason }.to_json)
  end
end
