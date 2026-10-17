# Claim commits before provider IO. Callers must not wrap this service in a
# transaction spanning the external call. An uncertain attempt needs manual review.
class Whatsapp::UnifiedDeliveryAttemptService
  class UncertainDelivery < StandardError; end

  REVIEW_ERROR = 'WhatsApp delivery confirmation is uncertain; review the message before retrying'.freeze

  def initialize(message:)
    @message = message
  end

  def perform
    return yield if @message.content_attributes.to_h['whatsapp_transport'].blank?

    decision = claim
    return if decision == :acknowledged
    return yield if decision == :legacy

    begin
      result = yield
    rescue StandardError
      finish(failed: true)
      raise
    end

    finish(failed: false)
    result
  end

  private

  def claim
    @message.with_lock do
      metadata = @message.content_attributes.to_h['whatsapp_transport']
      next :legacy if metadata.blank?
      next :acknowledged if @message.source_id.present?

      raise UncertainDelivery, REVIEW_ERROR if metadata['delivery_attempt_id'].present? || metadata['delivery_state'].present?

      attributes = @message.content_attributes.to_h.deep_dup
      attributes['whatsapp_transport'] = metadata.merge(
        'delivery_attempt_id' => SecureRandom.uuid,
        'delivery_attempted_at' => Time.current.iso8601(6),
        'delivery_state' => 'attempting'
      )
      @message.update!(content_attributes: attributes)
      :claimed
    end
  end

  def finish(failed:)
    @message.with_lock do
      state = !failed && @message.source_id.present? ? 'acknowledged' : 'uncertain'
      attributes = @message.content_attributes.to_h.deep_dup
      attributes['whatsapp_transport'] = attributes.fetch('whatsapp_transport').merge('delivery_state' => state)
      attributes['external_error'] = REVIEW_ERROR if state == 'uncertain'
      @message.update!(content_attributes: attributes)
    end
  end
end
