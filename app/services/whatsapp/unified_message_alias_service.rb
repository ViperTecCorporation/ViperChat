# Canonical alias adoption and monotonic delivery status synchronization.
# Callers retain ownership of the canonical record's ingestion lease and lock.
class Whatsapp::UnifiedMessageAliasService
  def initialize(record:, identity:, inbox:)
    @record = record
    @identity = identity
    @inbox = inbox
    @link = record.whatsapp_inbox_link
  end

  def link_identity
    alias_row = WhatsappUnifiedMessageAlias.find_by(whatsapp_message_identity: @identity)
    return @record.aliases.create_or_find_by!(whatsapp_message_identity: @identity) unless alias_row&.message_id

    if @record.message_id && @record.message_id != alias_row.message_id
      raise ArgumentError, 'Conflicting canonical message alias requires review' unless verified_copy?(alias_row.message)

      return alias_row.update!(whatsapp_unified_message: @record)
    end

    @record.update!(message: alias_row.message, state: 'ready',
                    media_inbox_id: alias_row.message.attachments.exists? ? @inbox.id : nil)
    alias_row.update!(whatsapp_unified_message: @record)
  end

  def merge_status
    return unless @record.message&.outgoing?

    statuses = @record.identities.flat_map { |identity| identity.observations.fetch('statuses', {}).keys }
    status = %w[read delivered sent].find { |value| statuses.include?(value) }
    order = %w[progress sent delivered read]
    return unless status

    @record.message.with_lock do
      @record.message.update!(status: status) if order.index(status).to_i > order.index(@record.message.status).to_i
    end
  end

  def compatible?(participant:, message_kind:)
    compatible_statuses = %w[matched participant_identity_pending]
    @record.participant_key == participant && @record.message_kind == message_kind &&
      @record.identities.all? do |identity|
        next true if identity.id == @identity.id
        next false if identity.inbox_id == @inbox.id

        status = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: identity.inbox).perform[:status]
        compatible_statuses.include?(status)
      end
  end

  private

  def verified_copy?(message)
    message.account_id == @link.account_id && @link.covers?(message.inbox) &&
      !message.private? && !message.web_attendance? && message.created_at >= @link.activated_at &&
      message.message_type == @record.direction && message.conversation.contact_id == @record.message.conversation.contact_id
  end
end
