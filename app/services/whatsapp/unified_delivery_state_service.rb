# Provider-scoped outcomes for one canonical bubble. A queue ID is not a receipt.
class Whatsapp::UnifiedDeliveryStateService
  KEY = 'whatsapp_delivery'.freeze
  ORDER = %w[progress sent delivered read].freeze
  SUCCESS = %w[read delivered sent].freeze

  def initialize(message:, inbox: message.inbox)
    @message = message
    @inbox = inbox
  end

  def record(state:, **details)
    return false unless ORDER.include?(state) || %w[failed uncertain].include?(state)
    return false unless Whatsapp::UnifiedDeliveryFallbackService.link_for(@message, inbox: @inbox)

    handled = @message.with_lock do
      @link = Whatsapp::UnifiedDeliveryFallbackService.link_for(@message, inbox: @inbox)
      next false unless @link

      attributes = @message.content_attributes.deep_dup
      event = delivery_event(state, details)
      record_outcome(attributes, event)
      cancel_unneeded_fallback(attributes, event)
      save_summary!(attributes)
      true
    end
    prepare_fallback if handled
    handled
  end

  def api_failure(response:, error:)
    return false unless Whatsapp::UnifiedDeliveryFallbackService.link_for(@message, inbox: @inbox)

    # HTTP 408 and server/network failures may have reached the provider.
    confirmed = response.code.to_i.in?(400..499) && response.code.to_i != 408
    parsed = response.parsed_response
    code = parsed.is_a?(Hash) ? parsed.dig('error', 'code') : nil
    record(state: confirmed ? 'failed' : 'uncertain', error: error, code: code || response.code.to_i,
           confirmed_failure: confirmed, origin: 'api')
  end

  def prepare_fallback
    Whatsapp::UnifiedDeliveryFallbackService.new(message: @message).perform
  end

  # The caller holds the message row lock, including when preparing a fallback.
  def save_summary!(attributes)
    outcomes = attributes.fetch(KEY, {})
    success = SUCCESS.find { |state| outcomes.values.any? { |row| row['state'] == state } }
    active = outcomes[attributes.dig('whatsapp_transport', 'provider')].to_h
    state = success || pending_or_failed(attributes, active)
    attributes.delete('external_error')
    attributes['external_error'] = active['error'] if state == 'failed'
    @message.update!(content_attributes: attributes, status: state)
  end

  private

  def delivery_event(state, details)
    event = details.merge(state: state, origin: details.fetch(:origin, 'webhook'))
    event[:state] = 'sent' if event[:origin] == 'echo' && state == 'delivered'
    event
  end

  def pending_or_failed(attributes, active)
    active['state'] == 'progress' || attributes.dig('whatsapp_transport', 'fallback_pending') ? 'progress' : 'failed'
  end

  def record_outcome(attributes, event)
    outcomes = previous_outcomes(attributes)
    previous = outcomes.fetch(@inbox.channel.provider, {})
    return if previous['state'] == 'failed' && event[:state].in?(%w[progress sent])

    row = if previous['state'].in?(%w[delivered read]) && event[:state].in?(%w[failed uncertain])
            previous.merge('warning' => safe_error(event[:error]))
          else
            outcome_row(previous, event, attributes)
          end
    outcomes[@inbox.channel.provider] = row
    attributes[KEY] = outcomes
  end

  def previous_outcomes(attributes)
    outcomes = attributes.fetch(KEY, {}).deep_dup
    return outcomes unless outcomes.empty? && @message.status.in?(%w[delivered read])

    metadata = attributes.fetch('whatsapp_transport')
    outcomes[metadata.fetch('provider')] = {
      'state' => @message.status, 'origin' => 'legacy_confirmation',
      'source_id' => metadata['provider_source_id'].presence || @message.source_id
    }
    outcomes
  end

  def outcome_row(previous, event, attributes)
    state = monotonic_state(previous['state'], event[:state])
    previous.merge(
      'state' => state, 'source_id' => event[:source_id].presence || previous['source_id'], 'origin' => event[:origin],
      'error' => state.in?(%w[failed uncertain]) ? safe_error(event[:error]) : nil,
      'code' => event[:code], 'confirmed_failure' => state == 'failed' && event[:confirmed_failure] == true,
      'attempt_id' => previous['attempt_id'] || attributes.dig('whatsapp_transport', 'delivery_attempt_id'),
      'updated_at' => Time.current.iso8601(6)
    ).compact
  end

  def monotonic_state(previous, incoming)
    ORDER.include?(incoming) && ORDER.index(previous).to_i > ORDER.index(incoming).to_i ? previous : incoming
  end

  def cancel_unneeded_fallback(attributes, event)
    metadata = attributes.fetch('whatsapp_transport')
    return unless metadata['fallback_pending'] && metadata['delivery_attempt_id'].blank?
    return unless event[:state].in?(%w[delivered read]) || (@inbox.channel.provider == metadata['provider'] && event[:state] == 'sent')

    attributes[KEY][metadata['provider']] = { 'state' => 'skipped', 'origin' => 'fallback' } if @inbox.channel.provider != metadata['provider']
    attributes['whatsapp_transport'] = metadata.merge(
      'provider' => @inbox.channel.provider, 'inbox_id' => @inbox.id, 'provider_source_id' => event[:source_id],
      'fallback_pending' => false, 'delivery_state' => 'acknowledged', 'reason' => 'late_confirmation'
    )
  end

  def safe_error(error)
    error.to_s.gsub(/Bearer\s+\S+/i, 'Bearer [FILTERED]')
         .gsub(/((?:access_token|api_key|token|password)=)[^\s&]+/i, '\\1[FILTERED]').truncate(400)
  end
end
