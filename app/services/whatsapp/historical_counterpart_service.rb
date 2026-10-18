# Runs while the canonical row is locked, before any historical media download.
class Whatsapp::HistoricalCounterpartService
  def initialize(inbox:, identity:, record:)
    @inbox = inbox
    @identity = identity
    @record = record
    @comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: identity, partner_inbox: record.whatsapp_inbox_link.partner_for(inbox))
  end

  def perform
    result = @comparison.perform
    return unless %w[matched participant_identity_pending].include?(result[:status]) && result[:candidate_identity_ids].one?

    identity = WhatsappMessageIdentity.find(result[:candidate_identity_ids].sole)
    message = counterpart_message(identity)
    return unless message

    @record.update!(message: message, state: 'ready', media_inbox_id: message.attachments.exists? ? identity.inbox_id : nil)
    @record.aliases.create_or_find_by!(whatsapp_message_identity: identity)
  end

  private

  def counterpart_message(identity)
    candidates = identity.messages.where(account_id: @inbox.account_id, private: false, delivery_destination: 'channel',
                                         message_type: @identity.observations['direction']).to_a
    raise ArgumentError, 'Ambiguous historical message copy' if candidates.many?
    return if candidates.empty?

    message = candidates.sole
    raise ArgumentError, 'Historical participant conflict' unless verified_contact?(identity, message.conversation.contact)

    message
  end

  def verified_contact?(identity, contact)
    key = Whatsapp::InboxLinkPhoneService.normalize(contact.phone_number)
    verifier = Whatsapp::MessageIdentityCorrelationService.new(identity: identity, partner_inbox: @inbox)
    key.present? && key == @record.participant_key && verifier.contact_matches_participant?(contact)
  end
end
