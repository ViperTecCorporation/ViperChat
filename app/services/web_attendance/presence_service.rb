# Call state-mutating methods while holding the conversation lock.
class WebAttendance::PresenceService
  FRESHNESS = 10.seconds

  def initialize(conversation)
    @conversation = conversation
  end

  def visible_sessions
    WebAttendanceSession.joins(:web_attendance_invitation)
                        .where(web_attendance_invitations: { conversation_id: @conversation.id, cycle: @conversation.web_attendance_cycle,
                                                             revoked_at: nil }).where.not(web_attendance_invitations: { activated_at: nil })
                        .where(visible: true).where('presence_seen_at >= ?', Time.current - FRESHNESS).select(&:visible_presence?)
  end

  def refresh!
    online = visible_sessions.any?
    return if online == @conversation.web_presence_online

    if online
      update_presence(web_presence_online: true, web_absent_since: nil,
                      web_absence_epoch: @conversation.web_absence_epoch + 1, web_reminder_pending_message_id: nil)
    else
      last_presence = WebAttendanceSession.joins(:web_attendance_invitation)
                                          .where(web_attendance_invitations: { conversation_id: @conversation.id,
                                                                               cycle: @conversation.web_attendance_cycle }).maximum(:presence_seen_at)
      absent_since = last_presence ? [last_presence + FRESHNESS, Time.current].min : Time.current
      update_presence(web_presence_online: false, web_absent_since: absent_since)
    end
  end

  def heartbeat!(session, visible, presence_id: 'legacy')
    refresh!
    now = Time.current
    entries = session.presence_entries.select { |_id, entry| entry['seen_at'].to_f >= (now - FRESHNESS).to_f }
    entries[presence_id] = { 'visible' => visible, 'seen_at' => now.to_f }
    session.presence_entries = entries
    session.update!(presence_seen_at: now, visible: session.visible_presence?(now))
    refresh!
  end

  private

  def update_presence(attributes)
    Current.with_web_attendance(@conversation) { @conversation.update!(attributes) }
  end
end
