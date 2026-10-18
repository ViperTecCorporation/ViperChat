# Selection is persisted before enqueue. A failed delivery is never permission to
# try the other provider. Public operational IDs always belong to that provider.
class Whatsapp::UnifiedTransportService
  class UnavailableReference < ArgumentError; end
  BASE = %w[text image audio video document sticker contacts location reaction quote].freeze
  UNO_ONLY = %w[edit delete view_once pix].freeze
  PROVIDERS = %w[unoapi whatsapp_cloud].freeze

  def self.capabilities(provider)
    result = (BASE + UNO_ONLY + ['template']).index_with do |capability|
      provider == 'unoapi' || (provider == 'whatsapp_cloud' && UNO_ONLY.exclude?(capability))
    end
    # The existing delete endpoint is local-only, not a provider revoke operation.
    result['delete'] = false
    result
  end

  def self.prepare!(message:, requested_provider: nil)
    return unless transport_message?(message)

    link = WhatsappInboxLink.for_inbox(message.inbox)
    raise ArgumentError, 'Transport selection requires an enabled inbox link' if requested_provider.present? && !link
    return unless link

    requested = requested_provider.presence || link.default_provider
    raise ArgumentError, 'Unknown WhatsApp transport' unless PROVIDERS.include?(requested)

    message.content_attributes = message.content_attributes.to_h.merge('whatsapp_transport' => transport_metadata(message, link, requested))
    Whatsapp::InitialMetaMessagesService.capture!(message, link: link)
  end

  def self.transport_message?(message)
    message.outgoing? && !message.private? && !message.web_attendance? && !message.conversation.group?
  end

  def self.transport_metadata(message, link, requested)
    capability = capability_for(message)
    effective = provider_for(requested, capability)
    {
      'link_id' => link.id, 'requested_provider' => requested, 'provider' => effective,
      'activation_cutoff' => link.activated_at.iso8601(6),
      'inbox_id' => link.inbox_for(effective).id, 'capability' => capability,
      'reason' => effective == requested ? 'selected' : 'capability_routing'
    }
  end

  def self.provider_for(preferred, capability)
    [preferred, *PROVIDERS].uniq.find { |provider| capabilities(provider)[capability] } ||
      raise(ArgumentError, 'This feature is not supported by the linked transports')
  end

  def self.capability_for(message)
    return 'template' if message.additional_attributes.to_h['template_params'].present?
    return 'pix' if message.content_attributes.to_h.dig('whatsapp_interactive', 'type') == 'payment_request'
    return 'view_once' if message.content_attributes.to_h['view_once'] == true
    return 'sticker' if message.content_type == 'sticker'

    'text'
  end

  def initialize(message:, operation: nil)
    @message = message
    @metadata = message.content_attributes.to_h['whatsapp_transport']
    select_operation(operation) if operation
  end

  def enabled?
    @metadata.present?
  end

  def inbox
    return @message.inbox unless enabled?

    link = WhatsappInboxLink.for_inbox(@message.inbox)
    selected = link&.inbox_for(@metadata['provider'])
    raise ArgumentError, 'The selected transport link changed; review the pending message' unless current_link?(link, selected)

    selected
  end

  def channel
    inbox.channel
  end

  def recipient
    return @message.conversation.group_source_id if @message.conversation.group?

    contact = @message.conversation.contact
    source = contact.contact_inboxes.where(inbox_id: inbox.id).order(:id).pluck(:source_id).find { |id| valid_recipient?(id) }
    source.presence || contact.phone_number&.delete_prefix('+').presence || raise(ArgumentError, 'Recipient identity pending for selected transport')
  end

  def reference_for(message)
    raise ArgumentError, 'Message reference is not available in this conversation' unless reference_allowed?(message)

    return message.source_id unless enabled?
    return message.source_id if message.content_attributes.dig('whatsapp_transport', 'inbox_id') == inbox.id

    provider_reference(message) || raise(UnavailableReference, 'Message reference is not available in the selected provider')
  end

  def reply_context
    reply_id = @message.content_attributes['in_reply_to']
    return if reply_id.blank? || skipped_quote?(reply_id)

    target = @message.conversation.messages.where(private: false).find_by(id: reply_id)
    return omit_quote(reply_id, 'target_unavailable') unless target

    reference = reference_for(target)
    reference.present? ? { message_id: reference } : omit_quote(reply_id, 'provider_reference_unavailable')
  rescue UnavailableReference
    omit_quote(reply_id, 'provider_reference_unavailable')
  end

  def register_source_id!(external_id)
    return unless enabled?

    identity = WhatsappMessageIdentity.create_or_find_by!(account_id: @message.account_id, inbox_id: inbox.id,
                                                          channel_id: channel.id, provider: channel.provider, external_id: external_id)
    WhatsappUnifiedMessageAlias.create_or_find_by!(whatsapp_message_identity: identity) { |row| row.message = @message }
    Whatsapp::MessageIdentityObservationService.new(inbox: inbox, value: {})
                                               .observe_api_response(message: @message, external_id: external_id)
  end

  def can_reply?
    return true if channel.provider == 'unoapi'

    [legacy_incoming_at, *provider_incoming_times].compact.max&.> 24.hours.ago
  end

  private

  def provider_reference(message)
    identity = reference_aliases(message).joins(:whatsapp_message_identity)
                                         .where(whatsapp_message_identities: { inbox_id: inbox.id, account_id: message.account_id })
                                         .first&.whatsapp_message_identity
    identity&.external_id.presence || legacy_reference(message)
  end

  def legacy_reference(message)
    return unless message.inbox_id == inbox.id && message.created_at < Time.iso8601(@metadata.fetch('activation_cutoff'))
    return if message.content_attributes['whatsapp_transport'].present? || message.content_attributes['whatsapp_unified_message_id'].present?

    source = message.source_id.to_s
    pattern = channel.provider == 'unoapi' ? /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i : /\Awamid\./
    source if source.match?(pattern)
  end

  def skipped_quote?(reply_id)
    fallback = @message.content_attributes['whatsapp_quote_fallback'].to_h
    fallback['in_reply_to'].to_s == reply_id.to_s && fallback['provider'] == @metadata['provider']
  end

  def omit_quote(reply_id, reason)
    @message.with_lock do
      attributes = @message.content_attributes.deep_dup
      attributes['whatsapp_quote_fallback'] = {
        'in_reply_to' => reply_id, 'provider' => @metadata.fetch('provider'),
        'reason' => reason, 'recorded_at' => Time.current.iso8601(6)
      }
      @message.update!(content_attributes: attributes)
    end
    nil
  end

  def current_link?(link, selected)
    link && selected && link.id == @metadata['link_id'] && selected.id == @metadata['inbox_id'] &&
      link.activated_at.iso8601(6) == @metadata['activation_cutoff']
  end

  def reference_allowed?(message)
    message.account_id == @message.account_id && message.conversation_id == @message.conversation_id &&
      !message.private? && !message.web_attendance?
  end

  def valid_recipient?(source)
    return source.present? if channel.provider == 'unoapi'

    source.to_s.match?(/\A(?:\d+|[A-Z]{2}\.\d{8,32})\z/)
  end

  def reference_aliases(message)
    WhatsappUnifiedMessageAlias.left_joins(:whatsapp_unified_message)
                               .where('whatsapp_unified_message_aliases.message_id = ? OR whatsapp_unified_messages.message_id = ?',
                                      message.id, message.id)
  end

  def legacy_incoming_at
    @message.conversation.messages.incoming.where(delivery_destination: 'channel', private: false, inbox_id: inbox.id)
            .with_content_attribute('whatsapp_unified_message_id', nil).maximum(:created_at)
  end

  def provider_incoming_times
    aliases = WhatsappUnifiedMessageAlias.joins(:whatsapp_message_identity, whatsapp_unified_message: :message)
                                         .where(messages: { conversation_id: @message.conversation_id, private: false,
                                                            delivery_destination: 'channel', message_type: Message.message_types[:incoming] })
                                         .where(whatsapp_message_identities: { inbox_id: inbox.id, account_id: @message.account_id,
                                                                               provider: 'whatsapp_cloud' })
    aliases.filter_map { |entry| incoming_time(entry.whatsapp_message_identity.observations) }
  end

  def incoming_time(observations)
    return unless observations['direction'] == 'incoming' && observations['timestamp'].to_s.match?(/\A\d+\z/)

    Time.zone.at(observations['timestamp'].to_i)
  end

  def select_operation(operation)
    return if @message.conversation.group?

    link = WhatsappInboxLink.for_inbox(@message.inbox)
    return unless link

    preferred = @metadata&.[]('provider') || @message.inbox.channel.provider
    provider = self.class.provider_for(preferred, operation)

    @metadata = { 'link_id' => link.id, 'provider' => provider, 'inbox_id' => link.inbox_for(provider).id,
                  'activation_cutoff' => link.activated_at.iso8601(6) }
  end
end
