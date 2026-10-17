# Observation only: never replaces source_id, sends messages or joins inboxes.
class Whatsapp::MessageIdentityObservationService
  PARTICIPANT_KEYS = %w[from to from_user_id to_user_id from_parent_user_id to_parent_user_id recipient_id recipient_type].freeze
  REFERENCE_KEYS = %w[id message_id original_message_id provider_message_id].freeze

  def initialize(inbox:, value:, outgoing_echo: false)
    @inbox = inbox
    @value = value.to_h.with_indifferent_access
    @outgoing_echo = outgoing_echo
  end

  def perform
    return unless %w[unoapi whatsapp_cloud].include?(@inbox.channel.provider)

    %i[messages message_echoes statuses].each do |kind|
      Array(@value[kind]).each { |event| observe(event.with_indifferent_access, kind) }
    end
  end

  # Also runs when an API send receives its source_id after an early status.
  def self.link_message(message)
    WhatsappMessageIdentity.where(account_id: message.account_id, inbox_id: message.inbox_id,
                                  provider: message.inbox.channel.provider, external_id: message.source_id).find_each do |identity|
      identity.message_links.create_or_find_by!(message: message)
    end
  end

  private

  def observe(event, kind)
    return unless observable_event?(event, kind)

    scope = identity_scope(event[:id])
    # Legacy Uno events need no new row, but may complete a pending observation.
    return if @inbox.channel.provider == 'unoapi' && event[:provider_message_id].blank? && !scope.exists?

    identity = scope.create_or_find_by!({})
    identity.with_lock do
      if @inbox.channel.provider == 'whatsapp_cloud'
        observe_meta_id(identity, event[:id])
      else
        merge_original_id(identity, event[:provider_message_id])
      end
      identity.observations = merge_observations(identity.observations, event, kind)
      identity.save! if identity.changed?
      identity.link_matching_messages
    end
  end

  def observable_event?(event, kind)
    # Sparse delivery echoes are not new messages and must not replace direction.
    event[:id].present? && (kind == :statuses || event[:type].present?)
  end

  def identity_scope(external_id)
    WhatsappMessageIdentity.where(account_id: @inbox.account_id, inbox_id: @inbox.id, channel_id: @inbox.channel_id,
                                  provider: @inbox.channel.provider, external_id: external_id)
  end

  def observe_meta_id(identity, external_id)
    parsed = Whatsapp::MetaMessageIdAdapter.parse(external_id)
    attributes = identity.observations
    attributes['meta_id_adapter'] = { 'version' => Whatsapp::MetaMessageIdAdapter::VERSION,
                                      'status' => parsed ? 'recognized' : 'unrecognized' }
    identity.observations = attributes
    return unless parsed

    merge_original_id(identity, parsed['provider_message_id'])
    attributes = identity.observations
    attributes['meta_id_adapter']['participant'] = parsed['participant']
    attributes['meta_id_adapter']['participant_type'] = parsed['participant_type']
    attributes['meta_id_adapter']['direction'] = parsed['direction']
    attributes['meta_id_adapter']['status'] = 'conflicting' if identity.provider_message_id != parsed['provider_message_id']
    identity.observations = attributes
  end

  def merge_original_id(identity, original)
    return if original.blank?

    if identity.provider_message_id.blank?
      identity.provider_message_id = original
    elsif identity.provider_message_id != original
      attributes = identity.observations
      attributes['conflicting_provider_message_ids'] = (Array(attributes['conflicting_provider_message_ids']) + [original]).uniq
      identity.observations = attributes
    end
  end

  def merge_observations(previous, event, kind)
    result = previous.deep_dup
    result['origin'] = 'webhook'
    result['contract_version'] = 1
    track_conflicts(result, result, { 'business_number' => @inbox.channel.phone_number })
    result['business_number'] ||= @inbox.channel.phone_number
    participants = event.slice(*PARTICIPANT_KEYS).stringify_keys.compact_blank
    track_conflicts(result, result.fetch('participants', {}), participants, 'participants.')
    result['participants'] = result.fetch('participants', {}).merge(participants)
    if kind == :statuses
      result['statuses'] = result.fetch('statuses', {}).merge(event[:status].to_s => event[:timestamp])
    else
      merge_message_observation(result, event, kind)
    end
    result
  end

  def merge_message_observation(result, event, kind)
    current = { 'direction' => kind == :message_echoes || @outgoing_echo ? 'outgoing' : 'incoming', 'message_type' => event[:type] }
    current.merge!(event.slice(:message_type, :edit_timestamp).stringify_keys.transform_keys('message_type' => 'event_type'))
    track_conflicts(result, result, current.slice('direction', 'message_type', 'event_type'))
    result.merge!(current.compact_blank)
    result['timestamp'] = event[:timestamp] if event.key?(:timestamp)
    %w[context reaction revoke].each do |reference|
      next unless event[reference].is_a?(Hash)

      result[reference] = result.fetch(reference, {}).merge(event[reference].slice(*REFERENCE_KEYS).stringify_keys)
    end
  end

  def track_conflicts(result, previous, current, prefix = '')
    current.each do |key, value|
      next if previous[key].blank? || value.blank? || previous[key] == value

      conflicts = result['conflicting_observations'] ||= {}
      field = "#{prefix}#{key}"
      conflicts[field] = (Array(conflicts[field]) + [previous[key], value]).uniq
    end
  end
end
