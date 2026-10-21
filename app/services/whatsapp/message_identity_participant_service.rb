# Comparison only. A LID is never a phone number, and receipts may describe the
# business device rather than the peer. Only established, account-scoped aliases
# may prove either role; no identifiers or contact records are rewritten.
class Whatsapp::MessageIdentityParticipantService
  def initialize(identity:)
    @identity = identity
  end

  def phone(value)
    Whatsapp::InboxLinkPhoneService.normalize(value)
  end

  def equivalent?(values, expected:)
    expected = phone(expected)
    expected.present? && values.all? { |value| phone(value) == expected || lid_phone(value) == expected }
  end

  def receipt_recipient?(values, peer:)
    return true if equivalent?(values, expected: peer)
    return false unless @identity.provider == 'unoapi' && @identity.observations['statuses'].present?
    return false if phone(peer).blank?

    values.all? { |value| phone(value) == phone(peer) || business_device?(value) }
  end

  def outgoing_bsuid_phone
    source = confirmed_outgoing_bsuid
    return if source.blank?

    ids = @identity.inbox.contact_inboxes.active_whatsapp_identity.where(source_id: source).pluck(:contact_id)
    contacts = @identity.inbox.account.contacts.where(id: ids).to_a
    phone(contacts.sole.phone_number) if contacts.one?
  end

  private

  def confirmed_outgoing_bsuid
    adapter = @identity.observations.fetch('meta_id_adapter', {})
    return unless @identity.provider == 'whatsapp_cloud' && @identity.observations['direction'] == 'outgoing'
    return unless adapter.values_at('status', 'direction', 'participant_type') == %w[recognized outgoing bsuid]

    source = adapter['participant']
    observed = @identity.observations.fetch('participants', {}).values_at('to_user_id', 'to_parent_user_id').find(&:present?)
    source if source.to_s.match?(/\A[A-Z]{2}\.\d{8,32}\z/) && observed == source
  end

  def business_device?(value)
    business = phone(@identity.observations['business_number'])
    business.present? && lid_phone(value) == business
  end

  def lid_phone(value)
    return unless value.to_s.match?(/\A[1-9][0-9]*@(hosted\.)?lid\z/)

    aliases = [value, value.sub('@hosted.lid', '@lid')].uniq
    ids = @identity.inbox.contact_inboxes.active_whatsapp_identity.where(source_id: aliases).pluck(:contact_id)
    contacts = @identity.inbox.account.contacts.where(id: ids).or(@identity.inbox.account.contacts.where(bsuid: aliases)).to_a
    phone(contacts.sole.phone_number) if contacts.one?
  end
end
