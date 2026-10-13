class WebAttendance::InvitationService
  def initialize(conversation:, user: nil)
    @conversation = conversation
    @user = user
  end

  def create!(content:, request_id:, greeting: false)
    @conversation.with_lock do
      ensure_available!
      validate_invitation_content!(content)

      existing = @conversation.messages
                              .with_content_attribute('web_invitation_cycle', @conversation.web_attendance_cycle)
                              .with_content_attribute('web_invitation_request_id', request_id).first
      next existing if existing
      next if greeting && @conversation.web_attendance_greeting_sent_at?

      unless @conversation.web_attendance_started_at?
        @conversation.update!(web_attendance_started_at: Time.current,
                              web_attendance_start_message_id: @conversation.messages.maximum(:id).to_i + 1)
      end
      invitation = build_invitation
      message = build_message(invitation, content, request_id, greeting)
      invitation.update!(message: message)
      @conversation.update!(web_attendance_greeting_sent_at: Time.current) if greeting
      message
    end
  end

  private

  def validate_invitation_content!(content)
    raise ArgumentError, 'The WhatsApp reply window is closed; an approved template is required' unless @conversation.can_reply?
    raise ArgumentError, 'Invitation message is empty' if content.blank?
    raise ArgumentError, 'Invitation message is too long' if content.length > @conversation.inbox.web_attendance_content_limit
  end

  def ensure_available!
    return if @conversation.inbox.web_attendance_available? && !@conversation.resolved? && !@conversation.group?

    raise ArgumentError, 'Web attendance is unavailable'
  end

  def build_invitation
    token = SecureRandom.urlsafe_base64(32)
    @conversation.web_attendance_invitations.create!(
      token_digest: Digest::SHA256.hexdigest(token), encrypted_token: WebAttendanceInvitation.encryptor.encrypt_and_sign(token),
      cycle: @conversation.web_attendance_cycle
    )
  end

  def build_message(invitation, content, request_id, greeting)
    @conversation.messages.create!(
      account: @conversation.account, inbox: @conversation.inbox, sender: @user,
      message_type: greeting ? :template : :outgoing, content: content,
      content_attributes: {
        web_invitation_request_id: request_id, web_invitation_cycle: invitation.cycle, web_attendance_invitation_id: invitation.id,
        web_attendance_cta: { title: @conversation.inbox.web_attendance_button_text }
      }
    )
  end
end
