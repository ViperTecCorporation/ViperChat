class WebAttendance::PresenceController < ApplicationController
  before_action :privacy_headers

  def create
    token = cookies.encrypted[:web_attendance_session].to_s
    session = WebAttendanceSession.find_by!(token_digest: Digest::SHA256.hexdigest(token))
    return head :unprocessable_entity unless valid_presence?

    session.conversation.with_lock do
      next head :gone unless session.reload.active?

      record_presence(session)
      head :no_content
    end
  rescue ActiveRecord::RecordNotFound
    head :gone
  end

  private

  def valid_presence?
    [true, false, 'true', 'false'].include?(params[:visible]) &&
      (params[:presence_id].nil? || params[:presence_id].to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i))
  end

  def record_presence(session)
    WebAttendance::PresenceService.new(session.conversation).heartbeat!(
      session, ActiveModel::Type::Boolean.new.cast(params[:visible]), presence_id: params[:presence_id] || 'legacy'
    )
  end

  def privacy_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    head :forbidden unless request.headers['X-Web-Attendance'] == '1'
  end
end
