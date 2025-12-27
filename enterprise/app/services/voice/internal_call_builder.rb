class Voice::InternalCallBuilder
  pattr_initialize [:account!, :conversation!, :inbox!, :user!, :target_agent!]

  def perform!
    Rails.logger.info(
      "VOICE_INTERNAL_CALL start " \
      "account_id=#{account.id} " \
      "conversation_id=#{conversation.display_id} " \
      "inbox_id=#{inbox.id} " \
      "user_id=#{user.id} " \
      "target_agent_id=#{target_agent.id}"
    )
    raise ArgumentError, 'Conversation is not internal chat' unless internal_conversation?
    raise ArgumentError, 'Voice inbox required' unless inbox.channel_type == 'Channel::Voice'
    raise ArgumentError, 'Custom voice provider required' unless inbox.channel.provider == 'custom'
    unless conversation.conversation_participants.exists?(user_id: target_agent.id)
      raise ArgumentError, 'Target agent is not a conversation participant'
    end

    timestamp = current_timestamp
    call_sid = SecureRandom.uuid
    conference_sid = Voice::Conference::Name.for(conversation)

    ActiveRecord::Base.transaction do
      update_conversation!(call_sid, conference_sid)
      build_voice_message!(call_sid, conference_sid, timestamp)
    end

    Rails.logger.info(
      "VOICE_INTERNAL_CALL created " \
      "account_id=#{account.id} " \
      "conversation_id=#{conversation.display_id} " \
      "call_sid=#{call_sid} " \
      "conference_sid=#{conference_sid}"
    )
    { conversation: conversation, call_sid: call_sid }
  end

  private

  def internal_conversation?
    conversation.inbox&.internal_chat? || conversation.additional_attributes&.dig('internal_chat')
  end

  def update_conversation!(call_sid, conference_sid)
    attrs = conversation.additional_attributes || {}
    attrs.merge!(
      'call_direction' => 'outbound',
      'call_status' => 'ringing',
      'agent_id' => user.id,
      'conference_sid' => conference_sid,
      'voice_inbox_id' => inbox.id,
      'call_type' => 'internal'
    )

    conversation.update!(
      identifier: call_sid,
      additional_attributes: attrs,
      last_activity_at: current_time
    )
  end

  def build_voice_message!(call_sid, conference_sid, timestamp)
    Voice::CallMessageBuilder.perform!(
      conversation: conversation,
      direction: 'outbound',
      payload: {
        call_sid: call_sid,
        status: 'ringing',
        call_type: 'internal',
        voice_inbox_id: inbox.id,
        conference_sid: conference_sid,
        from_number: inbox.channel&.phone_number,
        to_number: target_webrtc_username
      },
      user: user,
      timestamps: { created_at: timestamp, ringing_at: timestamp }
    )
  end

  def target_webrtc_username
    member = inbox.inbox_members.find_by(user_id: target_agent.id)
    return member.webrtc_username if member&.webrtc_username.present?

    target_agent.custom_attributes&.fetch('webrtc_username', nil).presence || target_agent.email
  end

  def current_timestamp
    @current_timestamp ||= current_time.to_i
  end

  def current_time
    @current_time ||= Time.zone.now
  end
end
