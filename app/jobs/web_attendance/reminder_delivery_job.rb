class WebAttendance::ReminderDeliveryJob < ApplicationJob
  queue_as :high

  def perform(message_id)
    message = Message.where.not(web_absence_request_key: nil).find_by(id: message_id)
    return unless message
    return unless claim_attempt(message)

    message.conversation.with_lock do
      next message.reload.update!(status: :failed, external_error: 'Web reminder cancelled: no longer eligible') unless deliverable?(message)

      Whatsapp::SendOnWhatsappService.new(message: message.reload).perform
      complete_delivery(message.reload)
    end
  rescue StandardError
    message&.reload&.update!(status: :failed, external_error: 'Web reminder failed: delivery uncertain; retry disabled')
    raise
  end

  private

  def claim_attempt(message)
    # Persist the attempt BEFORE network I/O: ambiguous failures must never cause a second WhatsApp send.
    # Atomic compare-and-set intentionally bypasses callbacks and validations.
    Message.where(id: message.id, web_reminder_attempted_at: nil)
           .update_all(web_reminder_attempted_at: Time.current) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  def complete_delivery(message)
    return message.update!(status: :sent) if message.source_id.present?

    message.update!(status: :failed, external_error: 'Web reminder failed: provider did not confirm delivery') unless message.failed?
  end

  def deliverable?(message)
    conversation = message.conversation
    WebAttendance::PresenceService.new(conversation).refresh!
    invitation = conversation.web_attendance_invitations.find_by(id: message.content_attributes['web_attendance_invitation_id'])
    return false unless invitation&.active? && conversation.can_reply? && !conversation.web_presence_online

    expected_key = "#{conversation.id}:#{conversation.web_attendance_cycle}:#{conversation.web_absence_epoch}"
    original = conversation.messages.find_by(id: message.content_attributes['web_absence_message_id'])
    message.content_attributes['web_absence_request_key'] == expected_key && original.present? && !original.read?
  end
end
