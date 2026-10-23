class Voip::ProviderEventContract
  TYPES = %w[call.created call.ringing participant.answered participant.released call.transferred call.ended call.updated
             recording.updated call.artifacts.updated].freeze
  STATES = %w[routing ringing active completed missed failed cancelled].freeze
  PARTICIPANT_STATES = %w[offered ringing active completed missed failed cancelled answered_elsewhere].freeze
  ENVELOPE_FIELDS = %w[schema_version event_id event_type occurred_at source_instance_id call_id revision call].freeze
  CALL_FIELDS = %w[direction state started_at answered_at ended_at from to end_reason participants recording artifacts].freeze
  PARTICIPANT_FIELDS = %w[id extension state started_at answered_at ended_at sip_call_id].freeze

  def self.validate!(payload, source:)
    new.validate!(payload, source: source)
  end

  def validate!(payload, source:)
    fields!(payload, ENVELOPE_FIELDS)
    invalid! unless payload['schema_version'].eql?(1) && TYPES.include?(payload['event_type'])
    %w[event_id source_instance_id call_id].each { |key| text!(payload[key], 200) }
    invalid! unless payload['source_instance_id'] == source
    revision!(payload['revision'])
    timestamp!(payload['occurred_at'])
    snapshot!(payload['call'])
    payload
  end

  private

  def fields!(value, allowed)
    invalid! unless value.is_a?(Hash) && (value.keys - allowed).empty?
  end

  def revision!(value)
    invalid! unless value.is_a?(Integer) && value.between?(1, 9_223_372_036_854_775_807)
  end

  def snapshot!(call)
    fields!(call, CALL_FIELDS)
    invalid! unless %w[inbound outbound internal].include?(call['direction']) && STATES.include?(call['state'])
    call_times!(call)
    call_addresses!(call)
    participants!(call['participants'])
    recording!(call['recording']) if call['recording']
    artifacts!(call['artifacts']) if call['artifacts']
  end

  def call_times!(call)
    timestamp!(call['started_at'])
    %w[answered_at ended_at].each { |key| timestamp!(call[key]) if call[key] }
  end

  def call_addresses!(call)
    text!(call['end_reason'], 128) if call['end_reason']
    %w[from to].each { |key| address!(call[key]) if call[key] }
  end

  def participants!(rows)
    invalid! unless rows.is_a?(Array) && rows.size <= 100
    rows.each { |participant| participant!(participant) }
    invalid! unless rows.pluck('id').uniq.size == rows.size
  end

  def recording!(recording)
    fields!(recording, %w[status record_id])
    invalid! unless %w[disabled recording processing available failed].include?(recording['status'])
    text!(recording['record_id'], 200)
  end

  def artifacts!(value)
    fields!(value, %w[recording ai note_target])
    artifact_recording!(value['recording']) if value['recording']
    artifact_ai!(value['ai']) if value['ai']
    return unless value['note_target']

    fields!(value['note_target'], %w[business_phone remote_phone])
    value['note_target'].values_at('business_phone', 'remote_phone').each do |phone|
      invalid! unless phone.is_a?(String) && phone.match?(/\A\+?\d{10,15}\z/)
    end
  end

  def artifact_recording!(value)
    fields!(value, %w[status record_id mime_type size_bytes sha256])
    recording!(value.slice('status', 'record_id'))
    invalid! if value.key?('mime_type') && Voip::RecordingClient::MIME_TYPES.exclude?(value['mime_type'])
    bounded_size!(value['size_bytes']) if value.key?('size_bytes')
    invalid! if value.key?('sha256') && !value['sha256'].to_s.match?(/\A[0-9a-f]{64}\z/)
  end

  def bounded_size!(value)
    invalid! unless value.is_a?(Integer) && value.between?(1, 50.megabytes)
  end

  def artifact_ai!(value)
    fields!(value, %w[status transcript summary transcription_model summary_model completed_at])
    invalid! unless %w[disabled queued processing completed failed].include?(value['status'])
    { 'transcript' => 64_000, 'summary' => 16_000, 'transcription_model' => 128, 'summary_model' => 128 }.each do |key, maximum|
      next unless value[key]

      multiline_text!(value[key], maximum)
    end
    timestamp!(value['completed_at']) if value['completed_at']
  end

  def multiline_text!(value, maximum)
    invalid! unless value.is_a?(String) && value.length <= maximum && !value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
  end

  def participant!(row)
    fields!(row, PARTICIPANT_FIELDS)
    invalid! unless PARTICIPANT_STATES.include?(row['state'])
    text!(row['id'], 200)
    text!(row['extension'], 128) if row['extension']
    text!(row['sip_call_id'], 256) if row['sip_call_id']
    %w[started_at answered_at ended_at].each { |key| timestamp!(row[key]) if row[key] }
  end

  def address!(row)
    fields!(row, %w[kind value name])
    invalid! unless %w[phone extension unknown].include?(row['kind'])
    text!(row['value'], 128)
    text!(row['name'], 128) if row['name']
    invalid! if row['kind'] == 'phone' && !row['value'].match?(/\A\+?\d{10,15}\z/)
  end

  def timestamp!(value)
    invalid! unless value.is_a?(String) && value.length <= 40 && value.match?(/(?:Z|\+00:00)\z/)
    Time.iso8601(value)
  rescue ArgumentError
    invalid!
  end

  def text!(value, maximum)
    invalid! unless value.is_a?(String) && value.present? && value.length <= maximum && !value.match?(/[\x00-\x1f\x7f]/)
  end

  def invalid!
    raise ArgumentError, 'invalid_voip_event'
  end
end
