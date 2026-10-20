# Identification only. Never merges established contacts, conversations or inboxes.
class Whatsapp::MessageIdentityContactResolver
  CONFIG_KEY = 'identity_resolution_partner_inbox_id'.freeze
  attr_reader :status

  def initialize(inbox:, message:)
    @inbox = inbox
    @message = message.to_h.with_indifferent_access
  end

  def perform
    return unless configured_partner
    return unless identity && verified_bsuid_event?

    # Serializes new aliases for this inbox. The unique source index also protects
    # against legacy creators; an existing owner is never reassigned.
    @inbox.with_lock { resolve }
  end

  # Only the enabled ingestion path may create a tracked technical placeholder.
  # Diagnostic callers of perform remain non-creating when evidence is missing.
  def pending_contact
    return unless configured_partner && identity && verified_bsuid_event? && status

    @inbox.with_lock do
      resolution = WhatsappIdentityResolution.create_or_find_by!(whatsapp_message_identity: @identity) do |row|
        row.partner_inbox = @partner
        row.reason = status
        row.next_attempt_at = Time.current
      end
      link = @inbox.contact_inboxes.find_by(source_id: @bsuid)
      link || create_provisional(resolution)
    end
  end

  private

  def create_provisional(resolution)
    contact = @inbox.account.contacts.create!(name: @bsuid)
    link = @inbox.contact_inboxes.create!(source_id: @bsuid, contact: contact,
                                          additional_attributes: { 'identity_provisional_resolution_id' => resolution.id })
    resolution.update!(provisional_contact_id: contact.id,
                       provisional_snapshot: Whatsapp::ProvisionalIdentityContactService.snapshot(contact))
    link
  end

  def configured_partner
    return unless @inbox.whatsapp? && @inbox.channel.provider == 'whatsapp_cloud'

    id = Integer(@inbox.channel.provider_config[CONFIG_KEY].to_s, exception: false)
    @partner ||= @inbox.account.inboxes.find_by(id: id)
    @partner if @partner&.channel.is_a?(Channel::Whatsapp) && @partner.channel.provider == 'unoapi'
  end

  def identity
    @identity ||= WhatsappMessageIdentity.find_by(account_id: @inbox.account_id, inbox_id: @inbox.id,
                                                  channel_id: @inbox.channel_id, provider: 'whatsapp_cloud', external_id: @message[:id])
  end

  def verified_bsuid_event?
    adapter = @identity.observations.fetch('meta_id_adapter', {})
    return false unless adapter['status'] == 'recognized' && adapter['participant_type'] == 'bsuid'
    return false unless supported_event?

    @bsuid = adapter['participant']
    keys = adapter['direction'] == 'outgoing' ? %i[to_user_id to_parent_user_id] : %i[from_user_id from_parent_user_id]
    keys.filter_map { |key| @message[key].presence }.first == @bsuid && @identity.observations['direction'] == adapter['direction']
  end

  def supported_event?
    @message[:message_type].blank? && %w[text image audio video document sticker contacts location button interactive].include?(@message[:type])
  end

  def resolve
    result = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @partner).perform
    return observe(result[:status]) unless %w[matched participant_identity_pending].include?(result[:status]) && result[:candidate_identity_ids].one?

    candidate = WhatsappMessageIdentity.find(result[:candidate_identity_ids].first)
    contact = candidate_contact(candidate)
    return observe('contact_identity_pending') unless contact

    link_alias(contact, candidate)
  end

  def candidate_contact(candidate)
    messages = candidate.messages.includes(conversation: :contact).to_a
    return unless messages.all? { |message| eligible_message?(message, candidate) }

    contacts = messages.map { |m| m.conversation.contact }.uniq(&:id)
    return unless contacts.one?

    verifier = Whatsapp::MessageIdentityCorrelationService.new(identity: candidate, partner_inbox: @inbox)
    contacts.first if verifier.contact_matches_participant?(contacts.first)
  end

  def eligible_message?(message, candidate)
    message.account_id == @inbox.account_id && message.inbox_id == @partner.id && !message.private? &&
      !message.conversation.group? && message.message_type == candidate_direction(candidate)
  end

  def candidate_direction(candidate)
    direction = candidate.observations['direction']
    direction ||= 'outgoing' if candidate.observations['statuses'].present? && candidate.observations.dig('participants', 'recipient_id').present?
    direction
  end

  def link_alias(contact, candidate)
    link = @inbox.contact_inboxes.create_or_find_by!(source_id: @bsuid) do |row|
      row.contact = contact
      row.additional_attributes = { 'message_identity_resolution' => { 'identity_id' => @identity.id, 'partner_identity_id' => candidate.id } }
    end
    unless link.contact_id == contact.id
      repair = Whatsapp::ProvisionalIdentityContactService.new(link: link, contact: contact)
      return observe(repair.status || 'alias_conflict') unless repair.perform

      link.reload
    end

    observe('reused_contact', contact_id: contact.id, partner_identity_id: candidate.id)
    link
  end

  def observe(status, **details)
    @status = status
    @identity.with_lock do
      @identity.observations = @identity.observations.merge('contact_resolution' => details.stringify_keys.merge('status' => status))
      @identity.save! if @identity.changed?
    end
    nil
  end
end
