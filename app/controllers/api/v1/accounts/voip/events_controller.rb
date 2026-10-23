class Api::V1::Accounts::Voip::EventsController < Api::V1::Accounts::Voip::BaseController
  prepend_before_action :require_integration_token
  before_action :check_admin_authorization?
  rescue_from Voip::ReceiveProviderEventService::Conflict do
    render json: { error: 'voip_event_identity_conflict' }, status: :conflict
  end

  def create
    service = services.find(params[:service_id])
    raise Pundit::NotAuthorizedError unless service.enabled? && %w[webhook viperconnect].include?(service.integration_provider)
    return render json: { error: 'voip_event_too_large' }, status: :payload_too_large if request.raw_post.bytesize > 256.kilobytes

    payload = JSON.parse(request.raw_post)
    event, duplicate = ::Voip::ReceiveProviderEventService.new(service: service, payload: payload).perform
    render json: { event_id: event.event_id, status: duplicate ? 'duplicate' : 'accepted' }, status: duplicate ? :ok : :accepted
  rescue JSON::ParserError
    render json: { error: 'invalid_voip_event' }, status: :unprocessable_entity
  end

  private

  def require_integration_token
    render json: { error: 'api_access_token_required' }, status: :unauthorized unless authenticate_by_access_token?
  end
end
