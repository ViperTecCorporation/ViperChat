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
    adopt_outbound_counterpart
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
      compatible_outbound_alias? &&
      @record.identities.all? do |identity|
        next true if identity.id == @identity.id
        next false if identity.inbox_id == @inbox.id

        status = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: identity.inbox).perform[:status]
        compatible_statuses.include?(status)
      end
  end

  # Read-only proof for the media reconciler. It may retain this one file, never
  # use an incomplete peer identity to replace/purge another stored copy.
  def verified_recipientless_copy?
    return false unless @record.message && recipientless_uno?

    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @link.partner_for(@inbox)).perform
    return false unless comparison[:status] == 'participant_identity_pending' && comparison[:candidate_identity_ids].one?

    row = @record.aliases.find_by(whatsapp_message_identity_id: comparison[:candidate_identity_ids].sole, message_id: @record.message_id)
    row && verified_outbound_alias?(row) &&
      @record.participant_key == Whatsapp::InboxLinkPhoneService.normalize(@record.message.conversation.contact.phone_number)
  end

  private

  def outbound_counterparts
    return [] unless @record.direction == 'outgoing' && @record.message_id.nil?

    @comparison ||= Whatsapp::MessageIdentityCorrelationService.new(identity: @identity, partner_inbox: @link.partner_for(@inbox)).perform
    @outbound_counterparts ||= WhatsappUnifiedMessageAlias.where(whatsapp_message_identity_id: @comparison[:candidate_identity_ids])
                                                          .where.not(message_id: nil).to_a
  end

  def compatible_outbound_alias?
    rows = outbound_counterparts
    rows.empty? || (rows.one? && compatible_outbound_comparison? && verified_outbound_alias?(rows.first))
  end

  def compatible_outbound_comparison?
    return true if @comparison[:status] == 'matched'

    @comparison[:status] == 'participant_identity_pending' && recipientless_uno?
  end

  def recipientless_uno?
    return false unless @identity.provider == 'unoapi' && @record.direction == 'outgoing'

    # A missing Uno recipient is not contradictory evidence. The exact Meta API
    # alias must still prove contact, business, link generation and public ID.
    participants = @identity.observations.fetch('participants', {})
    %w[to recipient_id to_user_id to_parent_user_id].all? { |key| participants[key].blank? }
  end

  def adopt_outbound_counterpart
    row = outbound_counterparts.sole unless outbound_counterparts.empty?
    return unless row

    row.lock!
    raise ArgumentError, 'Conflicting outbound alias requires review' unless compatible_outbound_alias?

    @record.update!(message: row.message, state: 'ready',
                    media_inbox_id: row.message.attachments.exists? ? row.whatsapp_message_identity.inbox_id : nil)
    row.update!(whatsapp_unified_message: @record)
  end

  def verified_outbound_alias?(row)
    message = row.message
    identity = row.whatsapp_message_identity
    (row.whatsapp_unified_message_id.nil? || row.whatsapp_unified_message_id == @record.id) &&
      verified_outbound_message?(message) && same_outbound_transport?(message, identity) &&
      Whatsapp::MessageIdentityCorrelationService.new(identity: identity, partner_inbox: @inbox)
                                                 .contact_matches_participant?(message.conversation.contact)
  end

  def same_outbound_transport?(message, identity)
    metadata = message.content_attributes['whatsapp_transport'].to_h
    message.source_id == identity.external_id && metadata['link_id'] == @link.id &&
      metadata['activation_cutoff'] == @link.activated_at.iso8601(6) &&
      ((metadata['inbox_id'] == identity.inbox_id && metadata['provider'] == identity.provider) ||
        acknowledged_uno_meta_echo?(metadata, identity))
  end

  def acknowledged_uno_meta_echo?(metadata, identity)
    return false unless identity.provider == 'whatsapp_cloud' && metadata['provider'] == 'unoapi'
    return false unless metadata['inbox_id'] == @link.inbox_for('unoapi').id && metadata['delivery_state'] == 'acknowledged'

    parsed = Whatsapp::MetaMessageIdAdapter.parse(identity.external_id)
    parsed && parsed['direction'] == 'outgoing' && parsed['provider_message_id'] == @record.original_id
  end

  def verified_outbound_message?(message)
    @link.reload.enabled? && primary_message_scope?(message) &&
      message.outgoing? && !message.private? && !message.web_attendance? && !message.conversation.group? &&
      message.created_at >= @link.activated_at
  end

  def primary_message_scope?(message)
    message.account_id == @link.account_id && message.inbox_id == @link.primary_inbox_id &&
      message.conversation.inbox_id == message.inbox_id && message.conversation.account_id == @link.account_id
  end

  def verified_copy?(message)
    message.account_id == @link.account_id && @link.covers?(message.inbox) &&
      !message.private? && !message.web_attendance? && message.created_at >= @link.activated_at &&
      message.message_type == @record.direction && message.conversation.contact_id == @record.message.conversation.contact_id
  end
end
