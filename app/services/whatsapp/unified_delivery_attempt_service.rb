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
    return if acknowledged?

    run_preflight(preflight) if preflight

    decision = claim
    return if decision == :acknowledged
    return yield if decision == :legacy

    begin
      result = yield
    rescue StandardError
      finish(failed: true)
      record_uncertain
      raise
    end

    complete
    result
  end

  private

  def complete
    finish(failed: false)
    record_uncertain if @message.content_attributes.dig('whatsapp_transport', 'delivery_state') == 'uncertain'
    Whatsapp::UnifiedDeliveryStateService.new(message: @message).prepare_fallback
  end

  def record_uncertain
    metadata = @message.content_attributes.fetch('whatsapp_transport')
    return if @message.content_attributes.dig(Whatsapp::UnifiedDeliveryStateService::KEY, metadata['provider'], 'state') == 'uncertain'

    target = @message.account.inboxes.find_by(id: metadata['inbox_id'])
    return unless target

    Whatsapp::UnifiedDeliveryStateService.new(message: @message, inbox: target)
                                         .record(state: 'uncertain', error: REVIEW_ERROR, origin: 'api')
  end

  def acknowledged?
    @message.reload
    metadata = @message.content_attributes.to_h['whatsapp_transport'].to_h
    acknowledged_metadata?(metadata)
  end

  def acknowledged_metadata?(metadata)
    metadata['provider_source_id'].present? || (@message.source_id.present? && metadata['fallback_from'].blank?)
  end

  def run_preflight(preflight)
    preflight.call
  rescue StandardError
    @message.with_lock do
      attributes = @message.content_attributes.deep_dup
      metadata = attributes.fetch('whatsapp_transport')
      next if metadata['delivery_attempt_id'].present? || (@message.source_id.present? && metadata['fallback_from'].blank?)

      attributes['whatsapp_transport'] = metadata.merge('delivery_state' => 'preflight_failed', 'fallback_pending' => false)
      attributes['external_error'] = PREFLIGHT_ERROR
      @message.update!(status: :failed, content_attributes: attributes)
    end
    record_preflight_failure
    raise
  end

  def record_preflight_failure
    metadata = @message.content_attributes.fetch('whatsapp_transport')
    target = @message.account.inboxes.find_by(id: metadata['inbox_id'])
    return unless target && metadata['delivery_state'] == 'preflight_failed'

    Whatsapp::UnifiedDeliveryStateService.new(message: @message, inbox: target)
                                         .record(state: 'failed', error: PREFLIGHT_ERROR, origin: 'preflight')
  end

  def claim
    @message.with_lock do
      metadata = @message.content_attributes.to_h['whatsapp_transport']
      next :legacy if metadata.blank?
      next :acknowledged if acknowledged_metadata?(metadata)

      state = metadata['delivery_state']
      raise UncertainDelivery, REVIEW_ERROR if blocked_claim?(metadata)

      attributes = @message.content_attributes.to_h.deep_dup
      attributes['whatsapp_transport'] = metadata.merge(
        'delivery_attempt_id' => SecureRandom.uuid,
        'delivery_attempted_at' => Time.current.iso8601(6),
        'delivery_state' => 'attempting', 'fallback_pending' => false
      )
      @message.update!(content_attributes: attributes, status: state == 'preflight_failed' ? :progress : @message.status)
      :claimed
    end
  end

  def blocked_claim?(metadata)
    state = metadata['delivery_state']
    pending_fallback = state == 'pending' && metadata['fallback_pending']
    metadata['delivery_attempt_id'].present? || (state.present? && state != 'preflight_failed' && !pending_fallback)
  end

  def finish(failed:)
    @message.with_lock do
      attributes = @message.content_attributes.to_h.deep_dup
      metadata = attributes.fetch('whatsapp_transport')
      state = completion_state(attributes, metadata, failed)
      attributes['whatsapp_transport'] = attributes.fetch('whatsapp_transport').merge('delivery_state' => state)
      attributes['external_error'] = REVIEW_ERROR if state == 'uncertain'
      attributes.delete('external_error') if state == 'acknowledged' && [REVIEW_ERROR, PREFLIGHT_ERROR].include?(@message.external_error)
      @message.update!(content_attributes: attributes, status: delivery_status(state))
    end
  end

  def completion_state(attributes, metadata, failed)
    return 'failed' if attributes.dig(Whatsapp::UnifiedDeliveryStateService::KEY, metadata['provider'], 'confirmed_failure')

    !failed && acknowledged_metadata?(metadata) ? 'acknowledged' : 'uncertain'
  end

  def delivery_status(state)
    state == 'acknowledged' && @message.progress? ? :sent : @message.status
  end
end
