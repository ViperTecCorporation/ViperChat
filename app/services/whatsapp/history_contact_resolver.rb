# Historical identities may enrich aliases, never replace an established owner.
class Whatsapp::HistoryContactResolver
  class Pending < StandardError; end

  def initialize(inbox:, peer:, message:)
    @inbox = inbox
    @peer = peer.to_s
    @message = message
    @phone = Whatsapp::InboxLinkPhoneService.normalize(@peer)
  end

  def perform
    Whatsapp::ContactIdentityLock.synchronize(account_id: @inbox.account_id, phone: @peer) { resolve_contact }
  end

  private

  def resolve_contact
    @inbox.with_lock do
      contacts = candidates
      raise Pending, 'Conflicting historical contact evidence' if contacts.many?

      contact = contacts.first || create_contact
      link = @inbox.contact_inboxes.create_or_find_by!(source_id: @peer) { |row| row.contact = contact }
      raise Pending, 'Established contact alias belongs to another contact' unless link.contact_id == contact.id

      link
    end
  end

  def candidates
    ids = @inbox.contact_inboxes.where(source_id: phone_variants + [@peer]).pluck(:contact_id)
    scope = @inbox.account.contacts.where(id: ids).or(@inbox.account.contacts.where(bsuid: @peer))
    scope = scope.or(@inbox.account.contacts.where(phone_number: phone_variants.map { |number| "+#{number}" })) if @phone
    contacts = scope.to_a
    identified = Whatsapp::MessageIdentityContactResolver.new(inbox: @inbox, message: @message).perform
    contacts << identified.contact if identified
    contacts.uniq(&:id)
  end

  def phone_variants
    Whatsapp::ContactIdentityLock.phone_variants(@peer)
  end

  def create_contact
    raise Pending, 'Historical BSUID needs verified phone or message evidence' unless @phone

    @inbox.account.contacts.create!(name: "+#{@phone}", phone_number: "+#{@phone}", historical_import: true)
  end
end
