class Voip::ReconcileProviderEventService
  TERMINAL_STATES = %w[completed missed failed cancelled].freeze
  STATE_MAP = { 'routing' => 'initiating', 'offered' => 'initiating', 'completed' => 'ended' }.freeze

  def initialize(event:)
    @event = event
    @service = event.voip_service
  end

  def perform
    changed = @service.with_lock do
      @event.reload
      next false if @event.processed_at

      identity = { voip_service: @service, source_instance_id: @event.source_instance_id, provider_call_id: @event.provider_call_id }
      @external = VoipExternalCall.find_or_create_by!(identity)
      if @event.revision > @external.revision
        apply_snapshot
        @event.update!(processed_at: Time.current)
        next true
      end
      @event.update!(processed_at: Time.current)
      false
    end
    broadcast if changed
    enqueue_artifact if changed && @external&.voip_call_artifact
  end

  private

  def apply_snapshot
    snapshot = normalize_snapshot(@event.payload.fetch('call').deep_dup)
    # Corrections/recordings may arrive after termination, but never resurrect the call.
    if TERMINAL_STATES.include?(@external.snapshot['state']) && TERMINAL_STATES.exclude?(snapshot['state'])
      snapshot['state'] = @external.snapshot['state']
      snapshot['ended_at'] = @external.snapshot['ended_at']
    end
    @external.update!(revision: @event.revision, snapshot: snapshot)
    persist_artifacts(snapshot['artifacts']) if snapshot['artifacts']
    snapshot.fetch('participants').each { |participant| project_participant(participant, snapshot) }
    Voip::PublishConversationCallService.new(external: @external).perform
  end

  def normalize_snapshot(snapshot)
    # Older producers cleared the aggregate answer timestamp at termination.
    # Only exact participant evidence can correct that summary; keep the event immutable.
    answered_at = snapshot.fetch('participants').filter_map { |participant| participant['answered_at'] }.min
    if snapshot['state'] == 'missed' && answered_at
      snapshot['state'] = 'completed'
      snapshot['answered_at'] = answered_at
    end
    snapshot
  end

  def persist_artifacts(snapshot)
    artifact = @external.voip_call_artifact || @external.build_voip_call_artifact
    # A destination is immutable once observed, even before a conversation exists.
    target = artifact.snapshot['note_target'] || snapshot['note_target']
    artifact.update!(snapshot: snapshot.merge(target ? { 'note_target' => target } : {}), desired_revision: @event.revision,
                     state: 'pending', attempts: 0, last_error_code: nil, next_attempt_at: nil)
  end

  def enqueue_artifact
    Voip::PublishCallArtifactJob.perform_later(@external.voip_call_artifact.id)
  rescue StandardError => e
    Rails.logger.warn("VoIP artifact enqueue unavailable (#{e.class.name})")
  end

  def project_participant(participant, snapshot)
    return if participant['sip_call_id'].blank? || participant['extension'].blank?

    binding = exact_binding(participant)
    return unless binding

    binding.account_user.with_lock { project_binding(binding, participant, snapshot) }
  end

  def project_binding(binding, participant, snapshot)
    call = exact_call(binding, participant)
    return unless call
    return if call.voip_external_call_id && call.voip_external_call_id != @external.id

    call.lock! if call.persisted?
    update_projection(call, participant, snapshot)
  end

  def update_projection(call, participant, snapshot)
    attributes = projection_attributes(participant, snapshot)
    if call.persisted? && VoipCall::TERMINAL_STATES.include?(call.state) && VoipCall::LIVE_STATES.include?(attributes[:state])
      attributes.merge!(state: call.state, answered_at: call.answered_at, ended_at: call.ended_at)
    end
    call.assign_attributes(attributes.merge(voip_external_call: @external,
                                            provider_participant_id: participant['id']))
    call.save!
  end

  def exact_binding(participant)
    bindings = @service.voip_agent_extensions.joins(:account_user).where(extension: participant['extension'],
                                                                         account_users: { account_id: @service.account_id })
    bindings.first if bindings.count == 1
  end

  def exact_call(binding, participant)
    matches = binding.voip_calls.where(sip_call_id: participant['sip_call_id'])
    return if matches.count > 1

    matches.first || binding.voip_calls.new(account_id: @service.account_id,
                                            client_call_id: "provider:#{Digest::SHA256.hexdigest([@external.id, participant['id']].join(':'))}",
                                            sip_call_id: participant['sip_call_id'], origin: 'provider_authoritative')
  end

  def projection_attributes(participant, snapshot)
    direction = local_direction(participant, snapshot)
    address = snapshot[direction == 'incoming' ? 'from' : 'to'] || { 'value' => 'unknown' }
    { direction: direction, remote_address: safe_remote_address(address), remote_name: address['name'], state: local_state(participant, snapshot),
      started_at: participant['started_at'] || snapshot.fetch('started_at'),
      answered_at: participant['answered_at'], ended_at: participant['ended_at'] || snapshot['ended_at'],
      end_reason: snapshot['end_reason'], last_observed_at: [Time.iso8601(@event.payload.fetch('occurred_at')), Time.current].min }
  end

  def local_direction(participant, snapshot)
    if snapshot['direction'] == 'internal'
      return snapshot.dig('to', 'value') == participant['extension'] ? 'incoming' : 'outgoing'
    end

    snapshot['direction'] == 'inbound' ? 'incoming' : 'outgoing'
  end

  def safe_remote_address(address)
    # No extraction of digits from LID/JID or untrusted identity strings.
    value = address['value'].to_s
    value.match?(/\A[a-zA-Z0-9_.+*#-]{1,128}\z/) ? value : 'unknown'
  end

  def local_state(participant, snapshot)
    state = STATE_MAP.fetch(participant['state'], participant['state'])
    state = STATE_MAP.fetch(snapshot['state'], snapshot['state']) if TERMINAL_STATES.include?(snapshot['state']) &&
                                                                     %w[initiating ringing active].include?(state)
    state
  end

  def broadcast
    Voip::BroadcastCallUpdateService.new(external: @external).perform
  end
end
