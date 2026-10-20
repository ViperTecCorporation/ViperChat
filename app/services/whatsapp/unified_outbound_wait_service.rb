# Wait only for an ambiguous send to this peer, never an unrelated contact.
# An exact API alias already has a response; ingestion still validates adoption.
class Whatsapp::UnifiedOutboundWaitService
  WAITING_STATES = %w[attempting uncertain].freeze

  def initialize(link:, identity:, participant:)
    @link = link
    @identity = identity
    @participant = participant
  end

  def waiting?
    return false unless @identity.observations['direction'] == 'outgoing'
    return false if confirmed_response?

    @link.primary_inbox.messages.outgoing.includes(conversation: :contact)
         .where(source_id: nil, status: %i[progress sent], private: false, delivery_destination: 'channel')
         .where('created_at >= ?', @link.activated_at).any? { |message| pending_for_peer?(message) }
  end

  private

  def confirmed_response?
    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @link.partner_for(@identity.inbox)).perform
    identities = [@identity.id]
    if %w[matched participant_identity_pending].include?(comparison[:status]) && comparison[:candidate_identity_ids].one?
      identities.concat(comparison[:candidate_identity_ids])
    end

    WhatsappUnifiedMessageAlias.joins(:message).where(whatsapp_message_identity_id: identities)
                               .where(messages: { account_id: @link.account_id, inbox_id: @link.primary_inbox_id, message_type: :outgoing,
                                                  private: false, delivery_destination: 'channel' })
                               .where.not(messages: { source_id: [nil, ''] }).exists?
  end

  def pending_for_peer?(message)
    metadata = message.content_attributes['whatsapp_transport']
    metadata && metadata['link_id'] == @link.id && metadata['activation_cutoff'] == @link.activated_at.iso8601(6) &&
      WAITING_STATES.include?(metadata['delivery_state']) &&
      Whatsapp::InboxLinkPhoneService.normalize(message.conversation.contact.phone_number) == @participant
  end
end
