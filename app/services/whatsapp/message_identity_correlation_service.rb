# Read-only observation for an explicitly selected pair, NOT message ingestion.
# No inbox discovery, contact merge, message linking, sending or media download.
class Whatsapp::MessageIdentityCorrelationService
  PHONE_OBSERVATION_FIELDS = %w[business_number participants.from participants.to participants.recipient_id].freeze

  def initialize(identity:, partner_inbox:)
    @identity = identity
    @partner = partner_inbox
  end

  def perform
    @identity.reload
    @partner.reload
    pending = scope_status
    return result(pending) if pending

    candidates = WhatsappMessageIdentity.where(account_id: @identity.account_id, inbox_id: @partner.id,
                                               channel_id: @partner.channel_id, provider: @partner.channel.provider,
                                               provider_message_id: @identity.provider_message_id).to_a
    return result('no_candidate') if candidates.empty?
    # Never pick one apparently compatible row out of a reused/conflicting ID.
    return result('ambiguous', candidates) if candidates.size != 1

    result(compatibility_status(candidates.first), candidates)
  end

  # Used only after an exact-message candidate has passed the scoped comparison.
  def contact_matches_participant?(contact)
    contact.account_id == @identity.account_id && phone(contact.phone_number).present? && phone(contact.phone_number) == peer(@identity)
  end

  def comparison_participant
    peer(@identity)
  end

  def safe_for_unification?
    scope_status.nil? && !observation_conflict?(@identity)
  end

  private

  def scope_status
    return 'invalid_scope' unless valid_scope?
    return 'business_identity_pending' unless observed_business?(@identity, business_number(@partner))
    return 'original_id_pending' if @identity.provider_message_id.blank?
    return 'conflicting_original_id' if conflicting?(@identity)

    nil
  end

  def compatibility_status(candidate)
    pending = evidence_status(candidate)
    return pending if pending
    return 'incompatible' if known_incompatibility?(candidate)
    return 'participant_identity_pending' unless complete_participant?(@identity) && complete_participant?(candidate)
    return 'incompatible' unless compatible?(candidate)

    'matched'
  end

  def evidence_status(candidate)
    return 'conflicting_original_id' if conflicting?(candidate)
    return 'conflicting_observations' if observation_conflict?(@identity) || observation_conflict?(candidate)
    return 'business_identity_pending' unless observed_business?(candidate, business_number(@identity.inbox))

    nil
  end

  def complete_participant?(identity)
    peer(identity).present? && direction(identity).present?
  end

  def valid_scope?
    @identity.inbox_id != @partner.id && @identity.account_id == @partner.account_id &&
      @identity.valid? && @partner.whatsapp? &&
      [@identity.provider, @partner.channel.provider].sort == %w[unoapi whatsapp_cloud] &&
      business_number(@identity.inbox).present? && business_number(@partner).present?
  end

  def business_number(inbox)
    phone(inbox.channel.phone_number)
  end

  def observed_business?(identity, expected)
    observed = phone(identity.observations['business_number'])
    observed.present? && observed == expected && observed == business_number(identity.inbox)
  end

  def phone(value)
    normalized = value.to_s.delete_prefix('+')
    return unless normalized.match?(/\A[1-9][0-9]{6,14}\z/)

    brazilian_mobile_comparison_phone(normalized)
  end

  # Comparison only: never save this key to channels, contacts or observations.
  def brazilian_mobile_comparison_phone(number)
    return number unless number.match?(/\A55[0-9]{2}[6-9][0-9]{7}\z/)

    candidate = Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(number)
    parsed = Phonelib.parse("+#{candidate}")
    parsed.valid? && parsed.type == :mobile ? candidate : number
  end

  def direction(identity)
    observations = identity.observations
    observations['direction'] || ('outgoing' if observations['statuses'].present? && observations.dig('participants', 'recipient_id').present?)
  end

  def peer(identity)
    participants = identity.observations.fetch('participants', {})
    return if participants['recipient_type'] == 'group' || participants.values.any? { |value| value.to_s.end_with?('@g.us') }

    raw = if direction(identity) == 'incoming'
            participants['from']
          elsif direction(identity) == 'outgoing'
            participants['to'] || participants['recipient_id']
          end
    phone(raw)
  end

  def conflicting?(identity)
    identity.observations['conflicting_provider_message_ids'].present? ||
      identity.observations.dig('meta_id_adapter', 'status') == 'conflicting'
  end

  def observation_conflict?(identity)
    observed_direction = direction(identity)
    envelope_direction = identity.observations.dig('meta_id_adapter', 'direction')
    conflicting_observations?(identity) ||
      (observed_direction.present? && envelope_direction.present? && observed_direction != envelope_direction) ||
      envelope_peer_conflict?(identity) || participant_role_conflict?(identity) || receipt_role_conflict?(identity)
  end

  def conflicting_observations?(identity)
    identity.observations.fetch('conflicting_observations', {}).any? do |field, values|
      next true unless PHONE_OBSERVATION_FIELDS.include?(field)
      next false if field == 'participants.recipient_id' && participant_service(identity).receipt_recipient?(Array(values), peer: peer(identity))

      keys = Array(values).map { |value| phone(value) }
      keys.include?(nil) || keys.uniq.size != 1
    end
  end

  def participant_role_conflict?(identity)
    participants = identity.observations.fetch('participants', {})
    to = phone(participants['to'])
    recipient = phone(participants['recipient_id'])
    (to.present? && recipient.present? && to != recipient) ||
      (direction(identity) == 'incoming' && recipient.present? && recipient != peer(identity)) || business_role_conflict?(identity)
  end

  def participant_service(identity)
    Whatsapp::MessageIdentityParticipantService.new(identity: identity)
  end

  def receipt_role_conflict?(identity)
    recipient = identity.observations.dig('receipt_participants', 'recipient_id')
    recipient.present? && !participant_service(identity).receipt_recipient?([recipient], peer: peer(identity))
  end

  def business_role_conflict?(identity)
    field = direction(identity) == 'outgoing' ? 'from' : 'to'
    raw = identity.observations.dig('participants', field)
    raw.present? && phone(raw) != phone(identity.observations['business_number'])
  end

  def envelope_peer_conflict?(identity)
    observed_peer = peer(identity)
    envelope_peer = phone(identity.observations.dig('meta_id_adapter', 'participant'))
    observed_peer.present? && envelope_peer.present? && observed_peer != envelope_peer
  end

  def known_incompatibility?(candidate)
    %w[event_type message_type].any? do |field|
      left = @identity.observations[field]
      right = candidate.observations[field]
      left.present? && right.present? && left != right
    end || (direction(@identity).present? && direction(candidate).present? && direction(@identity) != direction(candidate))
  end

  def compatible?(candidate)
    left = @identity.observations
    right = candidate.observations
    direction(@identity) == direction(candidate) && peer(@identity) == peer(candidate) &&
      left['event_type'] == right['event_type'] &&
      (left['message_type'].blank? || right['message_type'].blank? || left['message_type'] == right['message_type'])
  end

  def result(status, candidates = [])
    { status: status, identity_id: @identity.id, partner_inbox_id: @partner.id, candidate_identity_ids: candidates.map(&:id) }
  end
end
