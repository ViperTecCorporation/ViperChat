# Identity repair only: never replays ingestion or merges conversations/inboxes.
class Whatsapp::PendingIdentityResolutionService
  MAX_ATTEMPTS = 12
  CONFLICTS = %w[alias_conflict ambiguous conflicting_original_id conflicting_observations incompatible provisional_enriched].freeze

  def self.wake(identity)
    return if identity.provider_message_id.blank?

    WhatsappIdentityResolution.joins(:whatsapp_message_identity)
                              .where(partner_inbox_id: identity.inbox_id, state: %w[pending review])
                              .where(whatsapp_message_identities: { account_id: identity.account_id,
                                                                    provider_message_id: identity.provider_message_id })
                              .find_each do |resolution|
      resolution.with_lock do
        next unless %w[pending review].include?(resolution.state)

        resolution.update!(state: 'pending', next_attempt_at: Time.current)
      end
      Whatsapp::ResolvePendingIdentityJob.perform_later(resolution.id)
    end
  end

  def initialize(resolution:)
    @resolution = resolution
    @identity = resolution.whatsapp_message_identity
    @inbox = @identity.inbox
  end

  def perform
    # Same lock ordering as synchronous identification: inbox, resolution, contacts.
    @inbox.with_lock do
      @resolution.with_lock do
        next unless @resolution.state == 'pending' && @resolution.next_attempt_at && @resolution.next_attempt_at <= Time.current

        resolve
      end
    end
  rescue StandardError => e
    record_failure
    Rails.logger.warn("[WHATSAPP][IDENTITY] resolution_id=#{@resolution.id} error_class=#{e.class.name}")
    raise
  end

  private

  def record_failure
    @resolution.reload.with_lock do
      next unless @resolution.state == 'pending'

      attempts = @resolution.attempts + 1
      @resolution.update!(attempts: attempts, reason: 'processing_error', last_attempt_at: Time.current,
                          state: attempts >= MAX_ATTEMPTS ? 'review' : 'pending', next_attempt_at: 5.minutes.from_now)
    end
  end

  def resolve
    configured = @inbox.channel.provider_config[Whatsapp::MessageIdentityContactResolver::CONFIG_KEY].to_s
    unless configured == @resolution.partner_inbox_id.to_s
      return @resolution.update!(state: 'disabled', reason: 'configuration_changed', next_attempt_at: nil)
    end

    resolver = Whatsapp::MessageIdentityContactResolver.new(inbox: @inbox, message: event)
    record_result(resolver, resolver.perform)
  end

  def event
    observations = @identity.reload.observations
    event = observations.fetch('participants', {}).merge('id' => @identity.external_id, 'type' => observations['message_type'])
    event['message_type'] = observations['event_type'] if observations['event_type'].present?
    event
  end

  def record_result(resolver, link)
    attempts = @resolution.attempts + 1
    state = result_state(link, resolver.status, attempts)
    due_at = Time.current + [30 * (2**attempts), 3600].min.seconds if state == 'pending'
    @resolution.update!(state: state, reason: resolver.status || 'insufficient_evidence', attempts: attempts,
                        last_attempt_at: Time.current, next_attempt_at: due_at, resolved_contact_id: link&.contact_id)
  end

  def result_state(link, status, attempts)
    return 'resolved' if link
    return 'conflict' if CONFLICTS.include?(status)
    return 'review' if attempts >= MAX_ATTEMPTS || status.nil? || status == 'invalid_scope'

    'pending'
  end
end
