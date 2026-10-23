class Voip::PublishCallArtifactService
  def initialize(artifact:)
    @artifact = artifact
    @external = artifact.voip_external_call
    @service = @external.voip_service
  end

  def perform
    @artifact.reload
    return unless processing_allowed?

    revision = @artifact.desired_revision
    snapshot = @artifact.snapshot.deep_dup
    audio = fetch_recording(snapshot)
    changed = apply_artifacts(revision, snapshot, audio)
    Voip::BroadcastCallUpdateService.new(external: @external).perform if changed
  rescue StandardError => e
    retry_later(e)
  ensure
    audio&.dig(:file)&.close!
  end

  private

  def processing_allowed?
    !up_to_date? && valid_source? && @artifact.state != 'failed' && !@artifact.next_attempt_at&.future?
  end

  def valid_source?
    @service.enabled? && %w[webhook viperconnect].include?(@service.integration_provider) &&
      @service.credentials['webhook_source_instance_id'] == @external.source_instance_id
  end

  def up_to_date?
    @artifact.state == 'complete' && @artifact.applied_revision == @artifact.desired_revision
  end

  def apply_artifacts(revision, snapshot, audio)
    @artifact.with_lock do
      next if @artifact.desired_revision != revision

      attach_recording(audio) if audio && !@artifact.recording.attached?
      publish_note(snapshot)
      @artifact.update!(applied_revision: revision, attempts: 0, last_error_code: nil,
                        next_attempt_at: @artifact.state == 'complete' ? nil : 5.minutes.from_now)
    end
  end

  def retry_later(error)
    @artifact.with_lock do
      attempts = @artifact.attempts + 1
      @artifact.update!(state: attempts < 8 ? 'retry' : 'failed', attempts: attempts, last_error_code: 'artifact_processing_failed',
                        next_attempt_at: attempts < 8 ? [30 * (2**[attempts, 7].min), 3600].min.seconds.from_now : nil)
    end
    Rails.logger.warn("VoIP artifact processing failed (#{error.class.name})")
  end

  def fetch_recording(snapshot)
    recording = snapshot['recording']
    return unless recording&.[]('status') == 'available' && !@artifact.recording.attached?

    Voip::RecordingClient.new(@service).fetch(recording)
  end

  def attach_recording(audio)
    extension = { 'audio/mpeg' => 'mp3', 'audio/mp3' => 'mp3', 'audio/ogg' => 'ogg', 'audio/gsm' => 'gsm', 'audio/x-gsm' => 'gsm' }
    @artifact.recording.attach(io: audio.fetch(:file), filename: "call-#{@external.id}.#{extension.fetch(audio[:mime], 'wav')}",
                               content_type: audio.fetch(:mime))
    @artifact.recording_digest = audio.fetch(:digest)
  end

  def publish_note(snapshot)
    target = snapshot['note_target']
    unless target
      @artifact.state = 'complete'
      return
    end
    conversation = @artifact.conversation || Voip::ArtifactConversationResolver.new(service: @service, artifact: @artifact).resolve(target)
    return unless conversation

    @artifact.conversation = conversation
    unless @artifact.recording.attached? || snapshot.dig('ai', 'summary').present? || snapshot.dig('ai', 'transcript').present?
      @artifact.state = 'waiting_artifacts'
      return
    end
    update_note(conversation, snapshot)
    @artifact.state = 'complete'
  end

  def update_note(conversation, snapshot)
    note = @artifact.message || conversation.messages.new(account_id: @service.account_id, inbox_id: conversation.inbox_id,
                                                          message_type: :outgoing, private: true, source_id: "voip-artifact:#{@external.id}")
    note.content = note_text(snapshot)
    note.content_attributes = note.content_attributes.merge('voip_external_call_id' => @external.id.to_s)
    attach_note_recording(note)
    note.save!
    @artifact.message = note
  end

  def attach_note_recording(note)
    return unless @artifact.recording.attached? && note.attachments.none? { |row| row.file.blob_id == @artifact.recording.blob.id }

    note.attachments.build(account_id: @service.account_id, file_type: :audio, file: @artifact.recording.blob)
  end

  def note_text(snapshot)
    parts = ['Registro da ligação']
    parts << 'Gravação da ligação anexada.' if @artifact.recording.attached?
    ai = snapshot['ai'] || {}
    parts << "Resumo\n#{ai['summary']}" if ai['summary'].present?
    parts << "Transcrição\n#{ai['transcript']}" if ai['transcript'].present?
    parts.join("\n\n")
  end
end
