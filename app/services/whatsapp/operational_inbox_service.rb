# Operational entry points use the principal; administration still exposes both physical inboxes.
class Whatsapp::OperationalInboxService
  def self.canonical(inbox:, contact: nil, source_id: nil, conversation: nil)
    return inbox unless inbox&.whatsapp?
    # A caller-supplied group JID alone is not proof of a group conversation.
    return inbox if group?(contact, nil, conversation)
    return inbox if verified_group_source?(inbox, contact, source_id)

    WhatsappInboxLink.for_inbox(inbox)&.primary_inbox || inbox
  end

  def self.group?(contact, source_id, conversation = nil)
    conversation&.group? || [source_id, contact&.email].compact.any? { |value| value.to_s.end_with?('@g.us') }
  end

  def self.verified_group_source?(inbox, contact, source_id)
    return false unless source_id.to_s.end_with?('@g.us')

    scope = inbox.contact_inboxes.where(source_id: source_id)
    scope = scope.where(contact_id: contact.id) if contact
    scope.exists?
  end
  private_class_method :verified_group_source?

  def self.authorize!(inbox:, user:)
    raise Pundit::NotAuthorizedError unless accessible?(inbox, user)
  end

  def self.accessible?(inbox, user)
    return false unless user.is_a?(User) && Current.account&.id == inbox.account_id

    membership = user.account_users.find_by(account_id: inbox.account_id)
    return false unless membership

    context = { user: user, account: inbox.account, account_user: membership }
    Pundit.policy_scope!(context, Inbox).exists?(id: inbox.id)
  end

  def self.metadata(inbox:)
    link = WhatsappInboxLink.for_inbox(inbox)
    return unless link && accessible?(link.primary_inbox, Current.user)

    {
      link_id: link.id, primary_inbox_id: link.primary_inbox_id, primary_inbox_name: link.primary_inbox.name,
      secondary_inbox_id: link.secondary_inbox_id, default_provider: link.default_provider,
      transports: WhatsappInboxLink::PROVIDERS.map do |provider|
        transport = link.inbox_for(provider)
        { provider: provider, label: provider == 'unoapi' ? 'ViperConnect' : 'Meta', inbox_id: transport.id,
          channel_type: transport.channel_type, message_templates: transport.channel.message_templates || [],
          capabilities: Whatsapp::UnifiedTransportService.capabilities(provider) }
      end
    }
  end

  def self.contact_inbox(contact:, inbox:, source_id: nil)
    raise ArgumentError, 'Contact and inbox must belong to the same account' unless contact.account_id == inbox.account_id

    effective = canonical(inbox: inbox, contact: contact, source_id: source_id)
    contact.with_lock do
      existing = contact.contact_inboxes.where(inbox: effective).order(:id).first
      next existing if existing

      identity = contact_source_id(contact, effective, source_id)
      raise ArgumentError, 'Recipient identity pending for the principal inbox' if identity.blank?
      # Never move another contact's source ID or modify the secondary identity.
      raise ArgumentError, 'Recipient identity belongs to another contact' if ContactInbox.exists?(inbox: effective, source_id: identity)

      attributes = identity.start_with?('unified-contact:') ? { 'whatsapp_unified_pending_identity' => true } : {}
      ContactInbox.create!(contact: contact, inbox: effective, source_id: identity, hmac_verified: false, additional_attributes: attributes)
    end
  end

  def self.contact_source_id(contact, inbox, source_id)
    return source_id.presence || contact.email if group?(contact, source_id)
    return contact.phone_number.delete_prefix('+') if contact.phone_number.present?

    identity = contact.bsuid.presence
    return identity if inbox.channel.provider == 'unoapi' || identity.to_s.match?(/\A[A-Z]{2}\.\d{8,32}\z/)

    # A LID received by ViperConnect is not a valid Meta recipient identity.
    pending_meta_source(contact, inbox)
  end
  private_class_method :contact_source_id

  def self.pending_meta_source(contact, inbox)
    link = WhatsappInboxLink.for_inbox(inbox)
    return unless link && contact.contact_inboxes.exists?(inbox: link.inbox_for('unoapi'))

    # This new association is internal only; Meta's recipient validator must reject it.
    # It permits sending through the proven partner without inventing a Meta BSUID.
    "unified-contact:#{contact.id}"
  end
  private_class_method :pending_meta_source
end
