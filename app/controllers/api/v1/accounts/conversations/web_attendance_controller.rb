class Api::V1::Accounts::Conversations::WebAttendanceController < Api::V1::Accounts::Conversations::BaseController
  rescue_from ArgumentError, with: :render_validation_error

  def show
    render json: state
  end

  def create
    request_id = params.require(:request_id).to_s
    raise ArgumentError, 'Invalid request id' unless request_id.match?(/\A[\w-]{8,80}\z/)

    message = WebAttendance::InvitationService.new(conversation: @conversation, user: Current.user).create!(
      content: params.require(:content).to_s.first(4096), request_id: request_id
    )
    render json: { message: message.push_event_data }
  end

  def destroy
    @conversation.with_lock do
      @conversation.web_attendance_invitations.where(revoked_at: nil).find_each { |invite| invite.update!(revoked_at: Time.current) }
    end
    head :no_content
  end

  def seen
    destination = params.require(:destination)
    raise ArgumentError, 'Invalid destination' unless %w[channel web].include?(destination)

    column = destination == 'web' ? :web_agent_last_seen_at : :channel_agent_last_seen_at
    seen_at = Time.current
    if destination == 'web'
      Current.with_web_attendance(@conversation) { mark_destination_seen(destination, column, seen_at) }
    else
      mark_destination_seen(destination, column, seen_at)
    end
    Conversations::UnreadCounts::Notifier.new(@conversation).perform
    Conversations::UnreadCounts::FilteredCountInvalidator.new(Current.account).conversation_changed!
    render json: state
  end

  def fallback
    @conversation.with_lock do
      invitation = @conversation.web_attendance_invitations.find(params.require(:invitation_id))
      ensure_reply_window!
      raise ArgumentError, 'Invite is not eligible for text delivery' unless invitation.message.failed? && invitation.revoked_at.nil? &&
                                                                             invitation.cycle == @conversation.web_attendance_cycle &&
                                                                             !@conversation.resolved? && @conversation.inbox.web_attendance_available?

      invitation.message.update!(status: :progress,
                                 content_attributes: invitation.message.content_attributes.merge('web_attendance_text_fallback' => true))
      SendReplyJob.perform_later(invitation.message_id)
    end
    head :accepted
  end

  private

  def render_validation_error(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def ensure_reply_window!
    return if @conversation.can_reply?

    raise ArgumentError, 'The WhatsApp reply window is closed; an approved template is required'
  end

  def mark_destination_seen(destination, column, seen_at)
    @conversation.update!(column => seen_at)
    @conversation.messages.incoming.where(private: false, delivery_destination: destination).where.not(status: :read)
                 .where('created_at <= ?', seen_at).find_each { |message| message.update!(status: :read) }
  end

  def state
    invitations = @conversation.web_attendance_invitations.order(id: :desc)
    {
      enabled: @conversation.inbox.web_attendance_available?, active: invitations.any?(&:active?),
      unread: unread_counts, button_text: @conversation.inbox.web_attendance_button_text,
      provider: @conversation.inbox.channel.provider,
      can_invite: @conversation.inbox.web_attendance_available? && !@conversation.resolved? && @conversation.can_reply?,
      invitation_max_length: @conversation.inbox.web_attendance_content_limit,
      button_max_length: @conversation.inbox.web_attendance_button_limit,
      invitations: invitations.limit(5).map { |invitation| invitation_state(invitation) },
      metrics: invitation_metrics(invitations)
    }
  end

  def unread_counts
    %w[channel web].index_with do |destination|
      @conversation.unread_for_destination(destination).incoming.where(private: false).count
    end
  end

  def invitation_state(invitation)
    { id: invitation.id, status: invitation.message&.status, active: invitation.active?,
      failed: invitation.message&.failed?, error: invitation.message&.external_error }
  end

  def invitation_metrics(invitations)
    { invitations: invitations.count, openings: WebAttendanceSession.where(web_attendance_invitation: invitations).count,
      messages: @conversation.messages.where(delivery_destination: 'web').count }
  end
end
