class SendReplyJob < ApplicationJob
  queue_as :high
  retry_on ActiveRecord::RecordNotFound, wait: 30.seconds, attempts: 5

  CHANNEL_SERVICES = {
    'Channel::TwitterProfile' => ::Twitter::SendOnTwitterService,
    'Channel::TwilioSms' => ::Twilio::SendOnTwilioService,
    'Channel::Line' => ::Line::SendOnLineService,
    'Channel::Telegram' => ::Telegram::SendOnTelegramService,
    'Channel::Whatsapp' => ::Whatsapp::SendOnWhatsappService,
    'Channel::Sms' => ::Sms::SendOnSmsService,
    'Channel::Instagram' => ::Instagram::SendOnInstagramService,
    'Channel::Tiktok' => ::Tiktok::SendOnTiktokService,
    'Channel::Email' => ::Email::SendOnEmailService,
    'Channel::WebWidget' => ::Messages::SendEmailNotificationService,
    'Channel::Api' => ::Messages::SendEmailNotificationService
  }.freeze

  def perform(message_id)
    message = Message.find(message_id)
    return if handle_web_reply(message)

    channel_name = message.conversation.inbox.channel.class.to_s
    return send_on_facebook_page(message) if channel_name == 'Channel::FacebookPage'

    service_class = CHANNEL_SERVICES[channel_name]
    return unless service_class

    service_class.new(message: message).perform
    activate_web_invitation(message)
    ScheduledMessages::DeliveryStatusJob.perform_later(message.id) if ScheduledMessageItem.exists?(message_id: message.id)
  rescue StandardError => e
    ScheduledMessages::DeliveryStatusService.new(message).failed(e) if message
    raise
  end

  private

  def handle_web_reply(message)
    return true if message.web_attendance?
    return false if message.content_attributes['web_absence_request_key'].blank?

    WebAttendance::ReminderDeliveryJob.perform_later(message.id)
    true
  end

  def activate_web_invitation(message)
    invitation_id = message.content_attributes['web_attendance_invitation_id']
    return if message.source_id.blank? || invitation_id.blank?

    message.conversation.web_attendance_invitations.find(invitation_id).activate!
  end

  def send_on_facebook_page(message)
    if message.conversation.additional_attributes['type'] == 'instagram_direct_message'
      ::Instagram::Messenger::SendOnInstagramService.new(message: message).perform
    else
      ::Facebook::SendOnFacebookService.new(message: message).perform
    end
  end
end
