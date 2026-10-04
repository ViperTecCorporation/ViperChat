class WebAttendance::SessionsController < ApplicationController
  before_action :privacy_headers
  before_action :require_session, except: :create

  def show
    @conversation.with_lock do
      next head :gone unless @web_session.reload.active?

      messages = paginated_messages
      WebAttendance::DeliveryReceiptService.new(conversation: @conversation, messages: messages, message_type: 'outgoing').perform
      render json: { name: @conversation.inbox.name, contact_name: @conversation.contact.name,
                     messages: messages.map { |message| guest_message(message) },
                     has_more: more_messages?(messages) }
    end
  end

  def create
    token = params.require(:token).to_s
    invitation = WebAttendanceInvitation.find_by!(token_digest: Digest::SHA256.hexdigest(token))
    invitation.conversation.with_lock do
      next head :gone unless invitation.reload.active?

      session_token = SecureRandom.urlsafe_base64(32)
      invitation.web_attendance_sessions.create!(token_digest: Digest::SHA256.hexdigest(session_token), last_seen_at: Time.current)
      cookies.encrypted[:web_attendance_session] = {
        value: session_token, httponly: true, secure: request.ssl?, same_site: :strict, path: '/web-attendance/api'
      }
    end
    head :created unless performed?
  rescue ActiveRecord::RecordNotFound
    head :gone
  end

  def messages
    @conversation.with_lock do
      next head :gone unless @web_session.reload.active?

      message = WebAttendance::GuestMessageBuilder.new(@conversation, params).perform
      render json: guest_message(message), status: message.previously_new_record? ? :created : :ok
    end
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def seen
    @conversation.with_lock do
      next head :gone unless @web_session.reload.active?

      seen_at = Time.current
      Current.with_web_attendance(@conversation) do
        @web_session.update!(last_seen_at: seen_at)
        public_messages.outgoing.where(delivery_destination: 'web', status: [:sent, :delivered])
                       .where('created_at <= ?', seen_at).find_each { |message| message.update!(status: :read) }
      end
    end
    head :no_content unless performed?
  end

  def attachment
    @conversation.with_lock do
      next head :gone unless @web_session.reload.active?

      attachment = Attachment.where(message_id: public_messages.select(:id)).find(params[:id])
      next head :not_found unless attachment.file.attached?

      stream_attachment(attachment.file.blob)
    end
  end

  private

  def privacy_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    return if request.get? || request.headers['X-Web-Attendance'] == '1'

    head :forbidden
  end

  def require_session
    token = cookies.encrypted[:web_attendance_session].to_s
    @web_session = WebAttendanceSession.find_by!(token_digest: Digest::SHA256.hexdigest(token))
    @conversation = @web_session.conversation
    head :gone unless @web_session.active?
  rescue ActiveRecord::RecordNotFound
    head :gone
  end

  def public_messages
    scope = @conversation.messages.where(private: false, message_type: [:incoming, :outgoing, :template])
                         .with_content_attribute('web_attendance_invitation_id', nil)
    return scope.where('id >= ?', @conversation.web_attendance_start_message_id) if @conversation.web_attendance_start_message_id

    scope.where('created_at >= ?', @conversation.web_attendance_started_at)
  end

  def guest_message(message)
    WebAttendance::MessagePresenter.new(message).as_json
  end

  def paginated_messages
    scope = public_messages
    scope = scope.where('id < ?', params[:before].to_i) if params[:before].present?
    scope.reorder(id: :desc).limit(50).reverse
  end

  def more_messages?(messages)
    messages.present? && public_messages.exists?(['id < ?', messages.first.id])
  end

  def stream_attachment(blob)
    attachment_response = WebAttendance::AttachmentResponse.new(
      blob: blob, range_header: request.headers['Range'], download: params[:download] == '1'
    )
    self.response_body = attachment_response.apply(response)
  rescue WebAttendance::AttachmentResponse::InvalidRange
    head :range_not_satisfiable
  end
end
