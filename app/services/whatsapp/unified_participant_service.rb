class Whatsapp::UnifiedParticipantService
  def initialize(inbox:, identity:, link:)
    @inbox = inbox
    @identity = identity
    @link = link
  end

  def comparison
    @comparison ||= Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @link.partner_for(@inbox))
  end

  def eligible?
    comparison.safe_for_unification? && bsuid_role_matches?
  end

  def participant
    return @participant if defined?(@participant)

    @participant = comparison.comparison_participant
    return @participant if @participant

    bsuid = @identity.observations.dig('meta_id_adapter', 'participant')
    contact = @inbox.contact_inboxes.find_by(source_id: bsuid)&.contact if bsuid.present?
    @participant = Whatsapp::InboxLinkPhoneService.normalize(contact.phone_number) if contact
    @participant || resolve_counterpart
  end

  def contact_link(record:)
    return unless @resolved_contact

    source = @identity.observations.dig('meta_id_adapter', 'participant')
    return if source.blank?

    link = @inbox.contact_inboxes.create_or_find_by!(source_id: source) do |row|
      row.contact = @resolved_contact
      row.additional_attributes = { 'whatsapp_unified_message_id' => record.id }
    end
    raise ArgumentError, 'Established contact alias conflict requires review' unless link.contact_id == @resolved_contact.id

    link
  end

  private

  def bsuid_role_matches?
    adapter = @identity.observations.fetch('meta_id_adapter', {})
    return true unless adapter['participant_type'] == 'bsuid'

    keys = adapter['direction'] == 'outgoing' ? %i[to_user_id to_parent_user_id] : %i[from_user_id from_parent_user_id]
    observed = @identity.observations.fetch('participants', {}).with_indifferent_access
    keys.filter_map { |key| observed[key].presence }.first == adapter['participant']
  end

  def resolve_counterpart
    result = comparison.perform
    return unless %w[matched participant_identity_pending].include?(result[:status]) && result[:candidate_identity_ids].one?

    candidate = WhatsappMessageIdentity.find(result[:candidate_identity_ids].first)
    message = Whatsapp::UnifiedMessageIngestionService.message_for(candidate) ||
              candidate.messages.where(private: false, delivery_destination: 'channel').first
    return unless candidate_message?(message)

    verifier = Whatsapp::MessageIdentityCorrelationService.new(identity: candidate, partner_inbox: @inbox)
    return unless verifier.contact_matches_participant?(message.conversation.contact)

    @resolved_contact = message.conversation.contact
    @participant = verifier.comparison_participant
  end

  def candidate_message?(message)
    message && message.account_id == @inbox.account_id && !message.private? && !message.web_attendance? && !message.conversation.group?
  end
end
