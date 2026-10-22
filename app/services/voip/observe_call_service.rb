class Voip::ObserveCallService
  def initialize(call:, attributes:)
    @call = call
    @attributes = attributes.to_h.symbolize_keys
  end

  def perform
    @call.with_lock do
      sequence = Integer(@attributes.fetch(:sequence))
      event_id = @attributes.fetch(:event_id)
      existing = @call.voip_call_observations.find_by(event_id: event_id)
      if existing
        raise ArgumentError, 'voip_event_identity_conflict' unless existing.sequence == sequence && existing.state == @attributes.fetch(:state)

        next @call
      end

      state = @attributes.fetch(:state)
      @call.voip_call_observations.create!(event_id: event_id, sequence: sequence, state: state, details: details)
      next @call if sequence <= @call.last_sequence || VoipCall::TERMINAL_STATES.include?(@call.state)

      apply(state, sequence)
    end
    @call
  end

  private

  def details
    @attributes.slice(:sip_code, :end_reason, :resolved_address).compact
  end

  def apply(state, sequence)
    # A late ringing event cannot downgrade an established call, even with a newer sequence.
    return if @call.state == 'active' && %w[initiating ringing].include?(state)

    values = { state: state, last_sequence: sequence, last_observed_at: Time.current }
    values[:answered_at] = @call.answered_at || Time.current if state == 'active'
    values[:ended_at] = Time.current if VoipCall::TERMINAL_STATES.include?(state)
    values.merge!(details.slice(:sip_code, :end_reason))
    @call.update!(values)
  end
end
