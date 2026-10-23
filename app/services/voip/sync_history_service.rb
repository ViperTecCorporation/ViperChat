class Voip::SyncHistoryService
  RETRY_CODES = {
    'InvalidCursorError' => 'invalid_cursor', 'ScopeChangedError' => 'scope_changed',
    'AuthenticationError' => 'authentication_failed', 'UnsupportedError' => 'unsupported',
    'ConfigurationError' => 'configuration_required', 'Conflict' => 'revision_conflict'
  }.freeze

  def self.configuration_digest(service)
    values = service.credentials.slice('integration_provider', 'webhook_source_instance_id', 'history_api_url',
                                       'history_api_token', 'history_company_id')
    Digest::SHA256.hexdigest([service.id, service.account_id, values.sort].to_json)
  end

  def self.request(service:, reset_cursor: false, requested_by: nil)
    state = service.with_lock do
      row = service.history_sync_state || service.create_history_sync_state!
      row.assign_attributes(reset_requested: true, lease_token: nil, lease_expires_at: nil, last_reset_at: Time.current) if reset_cursor
      row.assign_attributes(last_requested_at: Time.current, last_requested_by_id: requested_by&.id)
      row.assign_attributes(state: 'pending', next_attempt_at: nil, last_error_code: nil) unless row.lease_expires_at&.future?
      row.save!
      row
    end
    enqueue_request(service)
    state
  end

  def self.enqueue_request(service)
    Voip::SyncHistoryJob.perform_later(service.id)
  rescue StandardError => e
    Rails.logger.warn("VoIP history scheduling unavailable (#{e.class.name})")
  end

  def initialize(service:)
    @service = service
  end

  def perform
    return @state unless claim

    cursor = @state.reset_requested? ? nil : @state.cursor
    page = Voip::WebhookHistoryClient.new(@service).fetch_webhook_events(cursor: cursor)
    events = persist_page(page)
    enqueue_events(events) if events
    @state
  rescue Voip::ServiceHistoryClient::Error, Voip::ReceiveProviderEventService::Conflict => e
    failed(e)
    @state
  end

  private

  def scope_digest
    self.class.configuration_digest(@service)
  end

  def configured?
    @service.enabled? && @service.integration_provider == 'viperconnect' && @service.credentials['history_company_id'].present?
  end

  def claim
    @service.with_lock do
      @state = @service.history_sync_state || @service.create_history_sync_state!
      next false unless configured_state
      next false if not_due?
      next false if VoipHistorySyncState::BLOCKED_STATES.include?(@state.state)

      @digest = scope_digest
      @token = SecureRandom.uuid
      @state.update!(scope_digest: @digest, lease_token: @token, lease_expires_at: 2.minutes.from_now,
                     state: 'running', last_attempt_at: Time.current)
      true
    end
  end

  def not_due?
    @state.lease_expires_at&.future? || @state.next_attempt_at&.future?
  end

  def configured_state
    unless configured?
      @state.update!(state: 'configuration_required', last_error_code: 'configuration_required', lease_token: nil, lease_expires_at: nil)
      return false
    end
    return true if @state.scope_digest == scope_digest

    @state.update!(state: 'pending', reset_requested: true, scope_digest: scope_digest, next_attempt_at: nil, last_error_code: nil)
    true
  end

  def persist_page(page)
    @service.with_lock do
      @state.reload
      next unless current_lease?

      rows = page.fetch('items').map do |item|
        Voip::ReceiveProviderEventService.new(service: @service, payload: item.fetch('webhook_event')).perform(enqueue: false).first
      end
      @state.cursor = page.fetch('nextCursor')
      @state.update!(state: page.fetch('hasMore') ? 'pending' : 'caught_up', reset_requested: false, failures: 0,
                     has_more: page.fetch('hasMore'), last_success_at: Time.current, last_error_code: nil,
                     next_attempt_at: page.fetch('hasMore') ? nil : 1.minute.from_now, lease_token: nil, lease_expires_at: nil)
      rows
    end
  end

  def current_lease?
    return false unless @state.lease_token == @token
    return true if @state.scope_digest == @digest && scope_digest == @digest && configured?

    @state.update!(state: 'pending', reset_requested: true, lease_token: nil, lease_expires_at: nil, next_attempt_at: nil)
    false
  end

  def enqueue_events(rows)
    rows.each { |event| Voip::ProcessProviderEventJob.perform_later(event.id) unless event.processed_at }
    Voip::SyncHistoryJob.perform_later(@service.id) if @state.has_more?
  rescue StandardError => e
    Rails.logger.warn("VoIP history enqueue unavailable (#{e.class.name})")
  end

  def failed(error)
    return unless @state && @token

    @service.with_lock do
      @state.reload
      next unless current_lease?

      code = error.class.name.demodulize
      attributes = failure_attributes(code)
      @state.update!(**attributes, failures: @state.failures + 1, lease_token: nil, lease_expires_at: nil)
    end
  end

  def failure_attributes(code)
    if code == 'CursorExpiredError'
      return { state: 'pending', reset_requested: true, gap_detected: true, last_error_code: 'cursor_expired', next_attempt_at: 1.minute.from_now }
    end

    blocked = RETRY_CODES[code]
    { state: blocked || 'retry', last_error_code: blocked || 'history_unavailable',
      next_attempt_at: blocked ? nil : [30 * (2**[@state.failures, 7].min), 3600].min.seconds.from_now }
  end
end
