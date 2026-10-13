class WebAttendance::AbsenceReminderService
  DELAY = 15.seconds
  CONTENT = 'Você tem uma nova mensagem. Clique no botão abaixo para continuar.'.freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def schedule!(message)
    @conversation.with_lock do
      WebAttendance::PresenceService.new(@conversation).refresh!
      next if message.read? || pending_check?

      update_state(web_reminder_pending_message_id: message.id)
      update_state(web_absent_since: Time.current) unless @conversation.web_presence_online || @conversation.web_absent_since
      enqueue(DELAY)
    end
  end

  def perform!(cycle, epoch)
    @conversation.with_lock { process_locked(cycle, epoch) }
  end

  private

  def pending_check?
    return true if @conversation.web_reminded_epoch == @conversation.web_absence_epoch

    pending = @conversation.messages.find_by(id: @conversation.web_reminder_pending_message_id)
    pending.present? && !pending.read?
  end

  def process_locked(cycle, epoch)
    return unless current_episode?(cycle, epoch) && active_invitation

    WebAttendance::PresenceService.new(@conversation).refresh!
    return unless epoch == @conversation.web_absence_epoch
    return update_state(web_reminder_pending_message_id: nil) if pending_cancelled?

    due_at = [@conversation.web_absent_since, pending_message.created_at].max + DELAY
    return enqueue(due_at - Time.current) if Time.current < due_at
    return unless @conversation.can_reply?

    create_reminder(cycle, epoch)
    update_state(web_reminded_epoch: epoch)
  end

  def update_state(attributes)
    Current.with_web_attendance(@conversation) { @conversation.update!(attributes) }
  end

  def pending_cancelled?
    @conversation.web_presence_online || pending_message.read?
  end

  def current_episode?(cycle, epoch)
    cycle == @conversation.web_attendance_cycle && epoch == @conversation.web_absence_epoch &&
      @conversation.web_reminder_pending_message_id.present? && @conversation.web_reminded_epoch != epoch
  end

  def create_reminder(cycle, epoch)
    @conversation.messages.create!(
      account: @conversation.account, inbox: @conversation.inbox, message_type: :outgoing, delivery_destination: 'channel',
      content: CONTENT, status: :progress,
      web_absence_request_key: "#{@conversation.id}:#{cycle}:#{epoch}",
      content_attributes: { web_attendance_invitation_id: active_invitation.id, web_absence_message_id: pending_message.id,
                            web_attendance_cta: { title: @conversation.inbox.web_attendance_button_text },
                            web_absence_request_key: "#{@conversation.id}:#{cycle}:#{epoch}" }
    )
  end

  def pending_message
    @conversation.messages.find(@conversation.web_reminder_pending_message_id)
  end

  def active_invitation
    @conversation.web_attendance_invitations.where(cycle: @conversation.web_attendance_cycle, revoked_at: nil)
                 .where.not(activated_at: nil).order(id: :desc).detect(&:active?)
  end

  def enqueue(delay)
    args = [@conversation.id, @conversation.web_attendance_cycle, @conversation.web_absence_epoch]
    WebAttendance::AbsenceReminderJob.set(wait: delay).perform_later(*args)
  end
end
