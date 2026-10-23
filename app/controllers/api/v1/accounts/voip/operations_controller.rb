class Api::V1::Accounts::Voip::OperationsController < Api::V1::Accounts::Voip::BaseController
  before_action :check_admin_authorization?
  rescue_from Voip::ReprocessPendingService::Conflict do
    render json: { error: 'voip_pending_reprocess_conflict' }, status: :conflict
  end

  def diagnostics
    render json: ::Voip::ProcessingDiagnosticsService.new(service: services.find(params[:service_id])).perform
  end

  def reprocess
    service = enabled_service!
    ::Voip::ReprocessPendingService.new(service: service, kind: params[:kind], record_id: params[:record_id], user: Current.user).perform
    render json: { status: 'queued', kind: params[:kind], record_id: params[:record_id].to_i }, status: :accepted
  end

  def recover_history
    service = enabled_service!
    raise Pundit::NotAuthorizedError unless service.integration_provider == 'viperconnect'
    raise ArgumentError, 'invalid_history_reset' if params.key?(:reset_cursor) && [true, false].exclude?(params[:reset_cursor])

    ::Voip::SyncHistoryService.request(service: service, reset_cursor: params[:reset_cursor] == true, requested_by: Current.user)
    render json: { status: 'queued' }, status: :accepted
  end

  private

  def enabled_service!
    service = services.find(params[:service_id])
    raise Pundit::NotAuthorizedError unless service.enabled? && %w[webhook viperconnect].include?(service.integration_provider)

    service
  end
end
