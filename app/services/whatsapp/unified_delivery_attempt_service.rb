# Claim commits before provider IO. Callers must not wrap this service in a
# transaction spanning the external call. An uncertain attempt needs manual review.
class Whatsapp::UnifiedDeliveryAttemptService
  class UncertainDelivery < StandardError; end

  REVIEW_ERROR = 'WhatsApp delivery confirmation is uncertain; review the message before retrying'.freeze
  PREFLIGHT_ERROR = 'Não foi possível preparar o envio. Nenhuma requisição foi enviada ao provedor.'.freeze

  def initialize(message:)
    @message = message
  end

  def perform(preflight: nil)
    return yield if @message.content_attributes.to_h['whatsapp_transport'].blank?
    return if @message.reload.source_id.present?

    run_preflight(preflight) if preflight

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

  def run_preflight(preflight)
    preflight.call
  rescue StandardError
    @message.with_lock do
      attributes = @message.content_attributes.deep_dup
      metadata = attributes.fetch('whatsapp_transport')
      next if @message.source_id.present? || metadata['delivery_attempt_id'].present?

      attributes['whatsapp_transport'] = metadata.merge('delivery_state' => 'preflight_failed')
      attributes['external_error'] = PREFLIGHT_ERROR
      @message.update!(status: :failed, content_attributes: attributes)
    end
    raise
  end

  def claim
    @message.with_lock do
      metadata = @message.content_attributes.to_h['whatsapp_transport']
      next :legacy if metadata.blank?
      next :acknowledged if @message.source_id.present?

      state = metadata['delivery_state']
      raise UncertainDelivery, REVIEW_ERROR if metadata['delivery_attempt_id'].present? || (state.present? && state != 'preflight_failed')

      attributes = @message.content_attributes.to_h.deep_dup
      attributes['whatsapp_transport'] = metadata.merge(
        'delivery_attempt_id' => SecureRandom.uuid,
        'delivery_attempted_at' => Time.current.iso8601(6),
        'delivery_state' => 'attempting'
      )
      @message.update!(content_attributes: attributes, status: state == 'preflight_failed' ? :progress : @message.status)
      :claimed
    end
  end

  def finish(failed:)
    @message.with_lock do
      state = !failed && @message.source_id.present? ? 'acknowledged' : 'uncertain'
      attributes = @message.content_attributes.to_h.deep_dup
      attributes['whatsapp_transport'] = attributes.fetch('whatsapp_transport').merge('delivery_state' => state)
      attributes['external_error'] = REVIEW_ERROR if state == 'uncertain'
      attributes.delete('external_error') if state == 'acknowledged' && [REVIEW_ERROR, PREFLIGHT_ERROR].include?(@message.external_error)
      @message.update!(content_attributes: attributes, status: delivery_status(state))
    end
  end

  def delivery_status(state)
    state == 'acknowledged' && @message.progress? ? :sent : @message.status
  end
end
