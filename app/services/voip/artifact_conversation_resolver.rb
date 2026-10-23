class Voip::ArtifactConversationResolver
  def initialize(service:, artifact:)
    @service = service
    @artifact = artifact
  end

  def resolve(target, call_event: false, open_incoming: false)
    @call_event = call_event
    @open_incoming = open_incoming
    inboxes = matching_inboxes(target['business_phone'])
    return unresolved('ambiguous') unless inboxes.one?

    inbox = inboxes.first
    variants = Whatsapp::CanonicalContactService.phone_variants(target['remote_phone'])
    return unresolved('pending_conversation') if variants.empty?

    ids = matching_contacts(inbox, variants)
    ids = [@service.account.contacts.create!(phone_number: "+#{variants.first}").id] if ids.empty? && @open_incoming
    return unresolved(ids.many? ? 'ambiguous' : 'pending_conversation') unless ids.one?

    matching_conversation(inbox, ids.first)
  end

  private

  def matching_conversation(inbox, contact_id)
    return call_conversation(inbox, contact_id) if @call_event

    conversations = @service.account.conversations.where(inbox_id: inbox.id, contact_id: contact_id).to_a.reject(&:group?)
    return unresolved(conversations.many? ? 'ambiguous' : 'pending_conversation') unless conversations.one?

    conversations.first
  end

  def call_conversation(inbox, contact_id)
    contact = @service.account.contacts.find(contact_id)
    latest = contact.conversations.where(inbox_id: inbox.id).order(created_at: :desc, id: :desc).detect { |row| !row.group? }
    return latest || unresolved('pending_conversation') unless @open_incoming

    if inbox.lock_to_single_conversation? && latest
      latest.open! if %w[resolved snoozed].include?(latest.status)
      return latest
    end
    contact_inbox = Whatsapp::OperationalInboxService.contact_inbox(contact: contact, inbox: inbox)
    return Conversation.create!(account: @service.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open)
  end

  def matching_inboxes(phone)
    matches = @service.account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).select do |inbox|
      Whatsapp::InboxLinkPhoneService.normalize(inbox.channel.phone_number) == Whatsapp::InboxLinkPhoneService.normalize(phone)
    end
    matches.map { |inbox| Whatsapp::OperationalInboxService.canonical(inbox: inbox) }.uniq(&:id)
  end

  def matching_contacts(inbox, variants)
    link = WhatsappInboxLink.for_inbox(inbox)
    proof_inboxes = link ? [link.primary_inbox_id, link.secondary_inbox_id] : [inbox.id]
    phones = variants.map { |number| "+#{number}" }
    ids = ContactInbox.where(inbox_id: proof_inboxes, source_id: variants + phones).pluck(:contact_id)
    (ids + @service.account.contacts.where(phone_number: phones).pluck(:id)).uniq
  end

  def unresolved(state)
    @artifact.state = state
    nil
  end
end
