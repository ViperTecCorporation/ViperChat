class Voice::CallMessageBuilder
  def self.perform!(conversation:, direction:, payload:, user: nil, timestamps: {})
    new(
      conversation: conversation,
      direction: direction,
      payload: payload,
      user: user,
      timestamps: timestamps
    ).perform!
  end

  def initialize(call = nil, **attributes)
    @call = call
    @conversation = attributes[:conversation]
    @direction = attributes[:direction]
    @payload = attributes[:payload]
    @user = attributes[:user]
    @timestamps = attributes.fetch(:timestamps, {})
  end

  def perform!
    return call.message || create_call_message! if call

    validate_sender!
    message = latest_message
    message ? update_message!(message) : create_message!
  end

  def update_status!(status:, agent: nil, duration_seconds: nil)
    message = call&.message
    return unless message

    patch = {
      'status' => status&.to_s&.tr('_', '-'),
      'accepted_by' => agent && { 'id' => agent.id, 'name' => agent.name },
      'duration_seconds' => duration_seconds
    }.compact

    message.update!(content_attributes: (message.content_attributes || {}).deep_merge('data' => patch))
    message
  end

  private

  attr_reader :call, :conversation, :direction, :payload, :user, :timestamps

  def create_call_message!
    params = {
      content: 'Voice Call',
      message_type: call.outgoing? ? 'outgoing' : 'incoming',
      content_type: 'voice_call',
      content_attributes: { 'data' => call_payload }
    }
    Messages::MessageBuilder.new(call_sender, call.conversation, params).perform
  end

  def call_sender
    call.outgoing? ? call.accepted_by_agent : call.contact
  end

  def call_payload
    {
      'call_id' => call.id,
      'call_sid' => call.provider_call_id,
      'call_source' => call.provider,
      'call_direction' => call.direction_label,
      'status' => call.display_status
    }
  end

  def latest_message
    conversation.messages.voice_calls.order(created_at: :desc).first
  end

  def update_message!(message)
    message.update!(
      message_type: message_type,
      content_attributes: { 'data' => base_payload },
      sender: sender
    )
  end

  def create_message!
    params = {
      content: 'Voice Call',
      message_type: message_type,
      content_type: 'voice_call',
      content_attributes: { 'data' => base_payload }
    }
    Messages::MessageBuilder.new(sender, conversation, params).perform
  end

  def base_payload
    @base_payload ||= begin
      data = payload.slice(
        :call_sid,
        :status,
        :call_direction,
        :call_type,
        :conference_sid,
        :from_number,
        :to_number,
        :voice_inbox_id
      ).stringify_keys
      data['call_direction'] = direction
      data['meta'] = {
        'created_at' => timestamps[:created_at] || current_timestamp,
        'ringing_at' => timestamps[:ringing_at] || current_timestamp
      }.compact
      data
    end
  end

  def message_type
    direction == 'outbound' ? 'outgoing' : 'incoming'
  end

  def sender
    return user if direction == 'outbound'

    conversation.contact
  end

  def validate_sender!
    return unless direction == 'outbound'

    raise ArgumentError, 'Agent sender required for outbound calls' unless user
  end

  def current_timestamp
    @current_timestamp ||= Time.zone.now.to_i
  end
end
