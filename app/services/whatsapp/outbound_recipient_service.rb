# Identity aliases remain unchanged. Choose an address only for the selected inbox.
class Whatsapp::OutboundRecipientService
  def initialize(conversation:, inbox:)
    @conversation = conversation
    @inbox = inbox
  end

  def perform
    return @conversation.group_source_id if @conversation.group?

    contact = @conversation.contact
    sources = contact.contact_inboxes.active_whatsapp_identity.where(inbox_id: @inbox.id).order(:id).pluck(:source_id)
    source = @inbox.channel.provider == 'whatsapp_cloud' ? meta_recipient(sources) : sources.find(&:present?)
    source.presence || contact.phone_number&.delete_prefix('+').presence || raise(ArgumentError, 'Recipient identity pending for selected transport')
  end

  private

  def meta_recipient(sources)
    # Keep Meta's actual phone representation (including Brazilian 8-digit mobiles).
    # An older BSUID alias must not hide a phone subsequently disclosed by Meta.
    sources.find { |source| source.to_s.match?(/\A[1-9]\d{6,14}\z/) } ||
      sources.find { |source| source.to_s.match?(/\A[A-Z]{2}\.\d{8,32}\z/) }
  end
end
