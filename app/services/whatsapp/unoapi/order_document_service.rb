class Whatsapp::Unoapi::OrderDocumentService
  def initialize(message:, payload:)
    @message = message
    @interactive = payload[:interactive].to_h.with_indifferent_access
  end

  def perform
    return false unless @interactive[:type] == 'order_details' && @interactive.dig(:header, :type) == 'document'

    @message.with_lock do
      next false if @message.attachments.any? { |attachment| attachment.meta&.dig('order_document') }

      attach_document
    end
  rescue SafeFetch::Error => e
    # Never log the signed URL or discard the order because its document is unavailable.
    Rails.logger.warn("[UnoAPI order document] message_id=#{@message.id} download_failed=#{e.class.name}")
    false
  end

  private

  def attach_document
    document = @interactive.dig(:header, :document).to_h.with_indifferent_access
    return false if document[:link].blank?

    SafeFetch.fetch(document[:link], allowed_content_type_prefixes: [],
                                     allowed_content_types: %w[application/pdf application/octet-stream]) do |download|
      # Upload while the SafeFetch tempfile is still open, even inside the caller's transaction.
      blob = ActiveStorage::Blob.create_and_upload!(
        io: download.tempfile,
        filename: document[:filename].presence || download.original_filename,
        content_type: document[:mime_type].presence || download.content_type
      )
      @message.attachments.create!(account_id: @message.account_id, file_type: :file,
                                   meta: { order_document: true }, file: blob)
    end
    true
  end
end
