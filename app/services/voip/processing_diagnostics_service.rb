class Voip::ProcessingDiagnosticsService
  def initialize(service:)
    @service = service
    @events = VoipProviderEvent.where(voip_service: @service).pending
    @artifacts = VoipCallArtifact.joins(:voip_external_call).where(voip_external_calls: { voip_service_id: @service.id }).where.not(state: 'complete')
  end

  def perform
    records = @events.order(created_at: :desc).limit(25).map { |row| event_payload(row) }
    records += @artifacts.order(created_at: :desc).limit(25).map { |row| artifact_payload(row) }
    { counts: counts,
      records: records.sort_by { |row| row[:created_at] }.reverse,
      truncated: @events.count > 25 || @artifacts.count > 25, recovery: @service.history_sync_payload }
  end

  private

  def counts
    { pending_events: @events.where('attempts < 8').count, failed_events: @events.where('attempts >= 8').count,
      pending_artifacts: @artifacts.where.not(state: 'failed').count, failed_artifacts: @artifacts.where(state: 'failed').count }
  end

  def event_payload(row)
    state = row.attempts.positive? ? 'retry' : 'pending'
    state = 'failed' if row.attempts >= 8
    base(row, 'event', state, row.source_instance_id)
  end

  def artifact_payload(row)
    base(row, 'artifact', row.state, row.voip_external_call.source_instance_id)
  end

  def base(row, kind, state, source)
    { kind: kind, id: row.id, state: state, attempts: row.attempts, last_error_code: row.last_error_code,
      next_attempt_at: row.next_attempt_at, created_at: row.created_at,
      reprocessable: @service.enabled? && %w[webhook viperconnect].include?(@service.integration_provider) &&
        @service.credentials['webhook_source_instance_id'] == source }
  end
end
