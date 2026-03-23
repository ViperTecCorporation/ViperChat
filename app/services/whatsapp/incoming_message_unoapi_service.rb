class Whatsapp::IncomingMessageUnoapiService < Whatsapp::IncomingMessageWhatsappCloudService
  private

  def process_messages
    return if mirrored_managed_whatsapp_message?

    super
  end

  def external_echo_message?
    outgoing_echo || managed_sender_matches_inbox?
  end

  def mirrored_managed_whatsapp_message?
    managed_sender_phone_number.present? && !managed_sender_matches_inbox?
  end

  def managed_sender_matches_inbox?
    managed_sender_phone_number.present? && managed_sender_phone_number == inbox_phone_number
  end

  def managed_sender_phone_number
    return @managed_sender_phone_number if defined?(@managed_sender_phone_number)

    sender_phone = message_sender_phone_number
    @managed_sender_phone_number =
      sender_phone.present? ? Channel::Whatsapp.find_by(phone_number: sender_phone)&.phone_number : nil
  end

  def message_sender_phone_number
    sender = messages_data&.first&.[](:from).to_s
    digits = sender.gsub(/\D/, '')
    return if digits.blank?

    "+#{digits}"
  end

  def inbox_phone_number
    @inbox_phone_number ||= inbox.channel.phone_number.to_s
  end
end
