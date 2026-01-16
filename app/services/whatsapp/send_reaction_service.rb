class Whatsapp::SendReactionService
  attr_reader :message, :emoji

  def initialize(message:, emoji:)
    @message = message
    @emoji = emoji
  end

  def perform
    return false unless message&.conversation&.inbox&.whatsapp?
    return false if message.source_id.blank?

    phone_number = reaction_recipient_phone_number
    return false if phone_number.blank?

    message.conversation.inbox.channel.send_reaction(
      phone_number,
      message.source_id,
      emoji
    )
  end

  private

  def reaction_recipient_phone_number
    contact_inbox = message.conversation.contact_inbox
    return if contact_inbox.blank?

    source_id = contact_inbox.source_id.to_s
    return if source_id.blank?

    uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    return source_id unless uuid_regex.match?(source_id)

    contact_inbox.contact.phone_number&.delete_prefix('+')
  end
end
