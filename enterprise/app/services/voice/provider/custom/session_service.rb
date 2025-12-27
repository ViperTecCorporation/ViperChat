class Voice::Provider::Custom::SessionService
  pattr_initialize [:conversation!, :inbox!, :user!]

  def join(call_sid:)
    Rails.logger.info(
      "VOICE_CUSTOM_SESSION_JOIN conversation_id=#{conversation.display_id} inbox_id=#{inbox.id} call_sid=#{call_sid} user_id=#{user.id}"
    )
    ensure_conference_sid!
    update_status('in-progress', call_sid)
    {
      status: 'success',
      id: conversation.display_id,
      conference_sid: conversation.additional_attributes['conference_sid'],
      using_webrtc: true,
      to: contact_phone_number
    }
  end

  def leave(call_sid:)
    Rails.logger.info(
      "VOICE_CUSTOM_SESSION_LEAVE conversation_id=#{conversation.display_id} inbox_id=#{inbox.id} call_sid=#{call_sid} user_id=#{user.id}"
    )
    update_status('completed', call_sid)
  end

  private

  def ensure_conference_sid!
    attrs = conversation.additional_attributes || {}
    return if attrs['conference_sid'].present?

    attrs['conference_sid'] = Voice::Conference::Name.for(conversation)
    conversation.update!(additional_attributes: attrs)
  end

  def update_status(status, call_sid)
    Voice::CallStatus::Manager.new(
      conversation: conversation,
      call_sid: call_sid
    ).process_status_update(status, timestamp: Time.zone.now.to_i)
  end

  def contact_phone_number
    conversation.contact&.phone_number || last_call_number
  end

  def last_call_number
    message = conversation.messages
                          .where(content_type: 'voice_call')
                          .order(created_at: :desc)
                          .first
    data = message&.content_attributes&.dig('data') || {}
    data['to_number'] || data['from_number']
  end
end
