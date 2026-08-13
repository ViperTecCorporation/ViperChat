module Whatsapp::Unoapi::LidIdentity
  LID_PATTERN = /\A(\d+)(?::\d+)?@lid\z/i

  module_function

  def canonicalize(value)
    match = LID_PATTERN.match(value.to_s.strip)
    return if match.blank?

    "#{match[1]}@lid"
  end

  def for_message(message, inbox:)
    return if message.blank? || message.conversation.group?

    inbox.contact_inboxes
         .where(contact_id: message.conversation.contact_id)
         .where("source_id ILIKE '%@lid'")
         .order(updated_at: :desc, id: :desc)
         .pluck(:source_id)
         .filter_map { |source_id| canonicalize(source_id) }
         .first
  end
end
