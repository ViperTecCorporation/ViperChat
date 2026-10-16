# Read-only observation for an explicitly selected pair, NOT message ingestion.
# No inbox discovery, contact merge, message linking, sending or media download.
class Whatsapp::MessageIdentityCorrelationService
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
    return 'participant_identity_pending' if brazilian_mobile_variant?(peer(@identity), peer(candidate))
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
    normalized if normalized.match?(/\A[1-9][0-9]{6,14}\z/)
  end

  # Candidate evidence only. Never normalize or merge a contact by this variant.
  def brazilian_mobile_variant?(left, right)
    shorter, longer = [left, right].sort_by(&:length)
    longer.match?(/\A55[1-9][0-9]9[6-9][0-9]{7}\z/) && shorter == longer[0, 4] + longer[5..]
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
    identity.observations['conflicting_observations'].present? ||
      (observed_direction.present? && envelope_direction.present? && observed_direction != envelope_direction) ||
      envelope_peer_conflict?(identity) || participant_role_conflict?(identity)
  end

  def participant_role_conflict?(identity)
    participants = identity.observations.fetch('participants', {})
    to = phone(participants['to'])
    recipient = phone(participants['recipient_id'])
    (to.present? && recipient.present? && to != recipient) ||
      (direction(identity) == 'incoming' && identity.observations['statuses'].present? && recipient.present?)
  end

  def envelope_peer_conflict?(identity)
    observed_peer = peer(identity)
    envelope_peer = identity.observations.dig('meta_id_adapter', 'participant')
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
