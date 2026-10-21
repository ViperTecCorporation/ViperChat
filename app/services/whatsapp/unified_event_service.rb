# Durable holding area, not another inbox. Unknown identity/early echoes never
# create a speculative contact or a second bubble. Payloads are not logged.
class Whatsapp::UnifiedEventService
  MAX_ATTEMPTS = 12

  def self.defer(link:, identity:, value:, reason:)
    event = WhatsappUnifiedEvent.create_or_find_by!(whatsapp_inbox_link: link, whatsapp_message_identity: identity) do |row|
      row.assign_attributes(payload: value, reason: reason, activation_cutoff: link.activated_at, next_attempt_at: 15.seconds.from_now)
      row.assign_attributes(state: 'review', next_attempt_at: nil) if %w[correlation_conflict link_changed].include?(reason)
    end
    if %w[correlation_conflict link_changed].include?(reason) && event.state == 'pending'
      event.update!(state: 'review', reason: reason, next_attempt_at: nil)
    end
    Whatsapp::ProcessUnifiedEventJob.set(wait: 15.seconds).perform_later(event.id) if event.previously_new_record? && event.state == 'pending'
    event
  end

  def self.wake(identity)
    events = WhatsappUnifiedEvent.joins(:whatsapp_message_identity)
                                 .where(state: 'pending', whatsapp_inbox_link_id: WhatsappInboxLink.active.covering(identity.inbox_id).select(:id))
    if identity.provider_message_id.present?
      events = events.where('whatsapp_message_identities.id = ? OR whatsapp_message_identities.provider_message_id = ?',
                            identity.id, identity.provider_message_id)
    end
    events = events.where(whatsapp_message_identity_id: identity.id) if identity.provider_message_id.blank?
    events.find_each do |event|
      event.with_lock do
        next unless event.state == 'pending'

        event.update!(next_attempt_at: Time.current)
        Whatsapp::ProcessUnifiedEventJob.perform_later(event.id)
      end
    end
  end

  def initialize(event:)
    @event = event
  end

  def perform
    @event.with_lock do
      next unless @event.state == 'pending'

      next @event.update!(state: 'review', reason: 'link_changed', next_attempt_at: nil) unless current_activation?
      next unless @event.next_attempt_at && @event.next_attempt_at <= Time.current

      process
    end
  rescue ArgumentError
    @event.reload.update!(state: 'review', reason: 'identity_conflict', next_attempt_at: nil, attempts: @event.attempts + 1)
  rescue StandardError => e
    Rails.logger.warn({ event: 'whatsapp_unified_event_retry', event_id: @event.id, error_class: e.class.name }.to_json)
    @event.reload.with_lock do
      next unless @event.state == 'pending'

      @event.reason = 'processing_error'
      retry_later
    end
  end

  private

  def current_activation?
    link = @event.whatsapp_inbox_link.reload
    link.enabled? && link.activated_at == @event.activation_cutoff
  end

  def process
    if Whatsapp::RetainedOutgoingEchoResolutionService.new(event: @event).perform ||
       Whatsapp::UnifiedEventResolutionService.new(event: @event).perform
      @event.update!(attempts: @event.attempts + 1)
      return
    end

    identity = @event.whatsapp_message_identity
    service = identity.provider == 'unoapi' ? Whatsapp::IncomingMessageUnoapiService : Whatsapp::IncomingMessageWhatsappCloudService
    value = @event.payload.with_indifferent_access
    params = { entry: [{ changes: [{ value: value }] }] }.with_indifferent_access
    service.new(inbox: identity.inbox, params: params, outgoing_echo: value[:message_echoes].present?).perform
    finish_replay(identity)
  end

  def finish_replay(identity)
    unless @event.reload.state == 'pending'
      @event.update!(attempts: @event.attempts + 1)
      return
    end

    message = Whatsapp::UnifiedMessageIngestionService.message_for(identity)
    if message&.persisted?
      @event.update!(state: 'completed', reason: 'correlated', payload: {}, next_attempt_at: nil, attempts: @event.attempts + 1)
    else
      retry_later
    end
  end

  def retry_later
    attempts = @event.attempts + 1
    state = attempts >= MAX_ATTEMPTS ? 'review' : 'pending'
    due = Time.current + [15 * (2**attempts), 3600].min.seconds if state == 'pending'
    @event.update!(attempts: attempts, state: state, next_attempt_at: due)
  end
end
