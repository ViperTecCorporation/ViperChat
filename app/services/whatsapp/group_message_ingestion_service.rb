# Group identities cannot use the one-to-one phone/BSUID participant resolver.
# Until Meta group-ID evidence is available, only exact, fully scoped copies of
# an existing Uno message may be adopted. Unknown Meta copies wait durably;
# Uno groups retain their existing path even when Meta is the primary inbox.
class Whatsapp::GroupMessageIngestionService
  def initialize(inbox:, value:)
    @inbox = inbox
    @value = value
    @link = WhatsappInboxLink.for_inbox(inbox)
    @uno_inbox = @link&.inbox_for('unoapi')
    @event = Array(value[:messages] || value[:message_echoes]).first.to_h.with_indifferent_access
  end

  def perform
    return yield unless @link && @inbox.channel.provider == 'whatsapp_cloud'

    @link.with_lock do
      next unless @link.enabled?

      identity = WhatsappMessageIdentity.find_by(inbox_id: @inbox.id, account_id: @inbox.account_id, external_id: @event[:id])
      next unless identity

      message = uno_copy(identity)
      if message
        row = WhatsappUnifiedMessageAlias.create_or_find_by!(whatsapp_message_identity: identity) { |item| item.message = message }
        next message if row.message_id == message.id
      end

      Whatsapp::UnifiedEventService.defer(link: @link, identity: identity, value: @value, reason: 'identity_pending')
      nil
    end
  end

  private

  def uno_copy(identity)
    return if identity.provider_message_id.blank? || conflicted?(identity)

    candidates = WhatsappMessageIdentity.where(account_id: @inbox.account_id, inbox_id: @uno_inbox.id,
                                               provider_message_id: identity.provider_message_id).to_a
    return unless candidates.one?

    candidate = candidates.sole
    return unless same_envelope?(identity, candidate)

    messages = uno_messages(candidate, identity)
    messages.sole if messages.one?
  end

  def uno_messages(candidate, identity)
    candidate.messages.where(inbox_id: @uno_inbox.id, private: false,
                             message_type: identity.observations['direction']).select do |message|
      message.conversation.group? && message.conversation.group_source_id == group_id(identity) &&
        message.created_at >= @link.activated_at && !message.web_attendance?
    end
  end

  def conflicted?(identity)
    identity.observations['conflicting_observations'].present? || identity.observations['conflicting_provider_message_ids'].present? ||
      identity.observations.dig('meta_id_adapter', 'status') == 'conflicting'
  end

  def same_envelope?(identity, candidate)
    return false if conflicted?(candidate)

    first = identity.observations
    second = candidate.observations
    same_business?(first, second) && same_participants?(identity, candidate) &&
      first['direction'].in?(%w[incoming outgoing]) && first['direction'] == second['direction'] &&
      first['message_type'].present? && first['message_type'] == second['message_type']
  end

  def same_participants?(identity, candidate)
    group_id(identity).present? && group_id(identity) == group_id(candidate) &&
      sender(identity).present? && sender(identity) == sender(candidate) && sender_evidence_agrees?(identity, candidate)
  end

  def sender_evidence_agrees?(identity, candidate)
    first = identity.observations.fetch('participants', {})
    second = candidate.observations.fetch('participants', {})
    %w[from from_user_id from_parent_user_id].all? do |key|
      first[key].blank? || second[key].blank? || first[key] == second[key]
    end
  end

  def same_business?(first, second)
    normalize = Whatsapp::InboxLinkPhoneService.method(:normalize)
    numbers = [first['business_number'], second['business_number'], @inbox.channel.phone_number,
               @uno_inbox.channel.phone_number].map(&normalize)
    numbers.all?(&:present?) && numbers.uniq.one?
  end

  def group_id(identity)
    identity.observations.dig('participants', 'group_id')
  end

  def sender(identity)
    participants = identity.observations.fetch('participants', {})
    participants['from'].presence || participants['from_parent_user_id'].presence || participants['from_user_id'].presence
  end
end
