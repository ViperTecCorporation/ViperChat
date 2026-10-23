class Voip::ReceiveProviderEventService
  class Conflict < StandardError; end

  def initialize(service:, payload:)
    @service = service
    @payload = Voip::ProviderEventContract.validate!(payload, source: service.credentials['webhook_source_instance_id'])
  end

  def perform(enqueue: true)
    # Serializes both event-id and call/revision uniqueness, without relying on the job queue for durability.
    result = @service.with_lock do
      digest = Digest::SHA256.hexdigest(canonical(@payload).to_json)
      scope = VoipProviderEvent.where(voip_service: @service, source_instance_id: @payload.fetch('source_instance_id'))
      existing = scope.find_by(event_id: @payload.fetch('event_id'))
      if existing
        raise Conflict unless existing.content_digest == digest

        next [existing, true]
      end
      raise Conflict if scope.exists?(provider_call_id: @payload.fetch('call_id'), revision: @payload.fetch('revision'))

      validate_recording_identity!

      event = scope.create!(event_id: @payload.fetch('event_id'), provider_call_id: @payload.fetch('call_id'),
                            revision: @payload.fetch('revision'), content_digest: digest, payload: @payload)
      [event, false]
    end
    enqueue(result.first) if enqueue
    result
  end

  private

  def validate_recording_identity!
    incoming = @payload.dig('call', 'artifacts', 'recording')
    return unless incoming

    artifact = stored_recording_artifact
    return unless artifact

    expected = { 'record_id' => artifact.snapshot.dig('recording', 'record_id'), 'sha256' => artifact.recording_digest,
                 'size_bytes' => artifact.recording.blob.byte_size }
    raise Conflict unless incoming.slice(*expected.keys).all? { |key, value| value == expected[key] }
  end

  def stored_recording_artifact
    external = VoipExternalCall.find_by(voip_service: @service, source_instance_id: @payload.fetch('source_instance_id'),
                                        provider_call_id: @payload.fetch('call_id'))
    artifact = external&.voip_call_artifact
    artifact if artifact&.recording&.attached?
  end

  def enqueue(event)
    Voip::ProcessProviderEventJob.perform_later(event.id) unless event.processed_at
  rescue StandardError => e
    # A scheduled recovery scans the durable inbox if Redis/enqueue is unavailable.
    Rails.logger.warn("VoIP webhook enqueue unavailable (#{e.class.name})")
  end

  def canonical(value)
    return value.sort.to_h.transform_values { |item| canonical(item) } if value.is_a?(Hash)
    return value.map { |item| canonical(item) } if value.is_a?(Array)

    value
  end
end
