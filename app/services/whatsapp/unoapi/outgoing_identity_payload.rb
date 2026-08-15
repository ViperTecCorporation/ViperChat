class Whatsapp::Unoapi::OutgoingIdentityPayload
  def initialize(request_body:, message:, inbox:)
    @request_body = request_body
    @message = message
    @inbox = inbox
  end

  def perform
    return request_body if group_message?

    payload = request_body.dup
    payload[recipient_key(payload)] = recipient if recipient.present?
    payload[:user_id] = lid if lid.present?
    payload[:username] = username if username.present?
    payload
  end

  private

  attr_reader :request_body, :message, :inbox

  def group_message?
    message&.conversation&.group?
  end

  def recipient
    current_recipient || lid || username
  end

  def current_recipient
    request_body[:to].presence || request_body['to'].presence
  end

  def recipient_key(payload)
    payload.key?('to') ? 'to' : :to
  end

  def lid
    @lid ||= Whatsapp::Unoapi::LidIdentity.for_message(message, inbox: inbox)
  end

  def username
    @username ||= message&.conversation&.contact&.whatsapp_username.to_s.strip.delete_prefix('@').downcase.presence
  end
end
