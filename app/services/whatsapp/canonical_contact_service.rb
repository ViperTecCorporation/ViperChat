# Select a proven older phone contact for NEW ingestion. Never moves aliases or history.
class Whatsapp::CanonicalContactService
  def self.phone_variants(value)
    phone = Whatsapp::InboxLinkPhoneService.normalize(value)
    return [] unless phone

    without_ninth = phone.sub(/\A(55\d{2})9(\d{8})\z/, '\1\2')
    [phone, without_ninth].uniq.select { |number| Whatsapp::InboxLinkPhoneService.normalize(number) == phone }
  end

  def initialize(identity:, link:)
    @identity = identity
    @link = link
  end

  def perform
    return unless eligible_scope?

    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @link.partner_for(@identity.inbox))
    return unless comparison.safe_for_unification?

    phone = comparison.comparison_participant
    return unless phone && legacy_alias

    candidate = phone_contact(phone)
    candidate if older_candidate?(candidate)
  end

  private

  def eligible_scope?
    @identity.provider == 'whatsapp_cloud' && @link.enabled? && @link.covers?(@identity.inbox)
  end

  def older_candidate?(candidate)
    candidate && candidate.id != legacy_alias.contact_id && candidate.created_at < legacy_alias.contact.created_at
  end

  def phone_contact(phone)
    candidates = @link.account.contacts.joins(:contact_inboxes)
                      .where(phone_number: self.class.phone_variants(phone).map { |number| "+#{number}" })
                      .where(contact_inboxes: { inbox_id: [@link.primary_inbox_id, @link.secondary_inbox_id] }).distinct.to_a
    raise ArgumentError, 'Ambiguous canonical phone contact requires review' if candidates.many?

    candidates.first
  end

  def observed_bsuid
    fields = @identity.observations['direction'] == 'outgoing' ? %w[to_parent_user_id to_user_id] : %w[from_parent_user_id from_user_id]
    participants = @identity.observations.fetch('participants', {})
    fields.filter_map { |field| participants[field].presence }.first
  end

  def legacy_alias
    return @legacy_alias if defined?(@legacy_alias)

    bsuid = observed_bsuid
    @legacy_alias = @identity.inbox.contact_inboxes.find_by(source_id: bsuid) if bsuid.to_s.match?(/\A[A-Z]{2}\.\d{8,32}\z/)
    @legacy_alias = nil if @legacy_alias&.contact&.phone_number.present?
    @legacy_alias
  end
end
