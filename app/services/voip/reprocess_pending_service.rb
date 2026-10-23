class Voip::ReprocessPendingService
  class Conflict < StandardError; end

  def initialize(service:, kind:, record_id:, user:)
    @service = service
    @kind = kind
    @record_id = record_id
    @user = user
  end

  def perform
    raise ArgumentError, 'invalid_voip_pending_kind' unless %w[event artifact].include?(@kind)

    row = @service.with_lock do
      item = pending_record
      item.with_lock { reset_record(item) }
      item
    end
    enqueue(row)
  end

  private

  def pending_record
    return VoipProviderEvent.where(voip_service: @service).find(@record_id) if @kind == 'event'

    VoipCallArtifact.joins(:voip_external_call).where(voip_external_calls: { voip_service_id: @service.id }).find(@record_id)
  end

  def reset_record(row)
    validate_retry!(row)
    attributes = { attempts: 0, next_attempt_at: nil, last_error_code: nil, last_reprocessed_at: Time.current,
                   last_reprocessed_by_id: @user.id }
    attributes[:state] = 'pending' if @kind == 'artifact'
    row.update!(attributes)
  end

  def validate_retry!(row)
    source = @kind == 'event' ? row.source_instance_id : row.voip_external_call.source_instance_id
    completed = @kind == 'event' ? row.processed_at.present? : row.state == 'complete'
    raise Conflict if completed || source != @service.credentials['webhook_source_instance_id']
    raise Conflict if row.last_reprocessed_at && row.last_reprocessed_at > 30.seconds.ago
  end

  def enqueue(row)
    job = @kind == 'event' ? Voip::ProcessProviderEventJob : Voip::PublishCallArtifactJob
    job.perform_later(row.id)
  rescue StandardError
    # The durable inbox and scheduled scanner retain the manual request if Redis is unavailable.
    Rails.logger.warn('VoIP manual processing enqueue unavailable')
  end
end
