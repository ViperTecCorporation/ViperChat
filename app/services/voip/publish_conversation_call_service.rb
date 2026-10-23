class Voip::PublishConversationCallService
  def initialize(external:)
    @external = external
    @service = external.voip_service
  end

  # Runs inside the service lock/event transaction. Retries update the same message.
  def perform
    snapshot = @external.snapshot
    return if snapshot['direction'] == 'internal'

    target = target_for(snapshot)
    return unless target

    artifact = @external.voip_call_artifact || @external.build_voip_call_artifact
    conversation = @external.conversation || resolve_conversation(artifact, target, snapshot)
    return unless conversation

    message = update_message(conversation, snapshot)
    @external.update!(conversation: conversation, call_message: message)
    link_artifact(artifact, conversation)
  end

  private

  def link_artifact(artifact, conversation)
    artifact.update!(conversation: conversation) if artifact.persisted? && artifact.conversation_id.nil?
  end

  def target_for(snapshot)
    target = snapshot.dig('artifacts', 'note_target')
    remote = snapshot[snapshot['direction'] == 'outbound' ? 'to' : 'from']
    if !target && snapshot['business_phone'] && remote&.[]('kind') == 'phone'
      target = { 'business_phone' => snapshot['business_phone'], 'remote_phone' => remote['value'] }
    end
    target
  end

  def resolve_conversation(artifact, target, snapshot)
    return artifact.conversation if artifact.message_id.present? && artifact.conversation_id.present?

    open_incoming = @service.credentials['reopen_on_incoming'] == true && snapshot['direction'] == 'inbound' &&
                    %w[routing ringing active].include?(snapshot['state']) && @external.call_message_id.nil?
    Voip::ArtifactConversationResolver.new(service: @service, artifact: artifact)
                                      .resolve(target, call_event: true, open_incoming: open_incoming)
  end

  def update_message(conversation, snapshot)
    message = @external.call_message || @external.voip_call_artifact&.message || conversation.messages.new(
      account: @service.account, inbox: conversation.inbox, private: true,
      content_type: :voice_call, source_id: "voip-call:#{@external.id}"
    )
    message.assign_attributes(content: 'Voice Call', content_type: :voice_call, private: true,
                              message_type: snapshot['direction'] == 'inbound' ? :incoming : :outgoing,
                              sender: conversation.contact, content_attributes: preserved_attributes(message).merge(attributes(snapshot)))
    message.save! if message.new_record? || message.changed?
    message
  end

  def preserved_attributes(message)
    return message.content_attributes unless message.persisted? && message.content_type != 'voice_call'

    message.content_attributes.merge('voip_legacy_content' => message.content)
  end

  def attributes(snapshot)
    answered = @external.voip_calls.where.not(answered_at: nil).order(:answered_at).first
    duration = if snapshot['answered_at'] && snapshot['ended_at']
                 [(Time.iso8601(snapshot['ended_at']) - Time.iso8601(snapshot['answered_at'])).to_i, 0].max
               end
    { 'voip_external_call_id' => @external.id, 'data' => {
      'state' => snapshot['state'], 'direction' => snapshot['direction'], 'service_name' => @service.name,
      'extension' => answered&.local_extension, 'agent_id' => answered&.local_agent_id,
      'started_at' => snapshot['started_at'], 'answered_at' => snapshot['answered_at'], 'ended_at' => snapshot['ended_at'],
      'duration_seconds' => duration, 'end_reason' => snapshot['end_reason']
    }.compact }
  end
end
