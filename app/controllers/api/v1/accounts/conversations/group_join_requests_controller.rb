class Api::V1::Accounts::Conversations::GroupJoinRequestsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_group_conversation
  before_action :ensure_session_group_admin

  def index
    response = provider_service.group_join_requests(@conversation.group_source_id)
    return render json: response.parsed_response if response.success?

    render json: { error: provider_error(response, 'Provider failed to fetch join requests') }, status: :unprocessable_entity
  end

  def create
    response = provider_service.approve_group_join_requests(
      group_id: @conversation.group_source_id,
      participants: participants
    )
    return render json: response.parsed_response if response.success?

    render json: { error: provider_error(response, 'Provider failed to approve join requests') }, status: :unprocessable_entity
  end

  def destroy
    response = provider_service.reject_group_join_requests(
      group_id: @conversation.group_source_id,
      participants: participants
    )
    return render json: response.parsed_response if response.success?

    render json: { error: provider_error(response, 'Provider failed to reject join requests') }, status: :unprocessable_entity
  end

  private

  def provider_service
    @provider_service ||= @conversation.inbox.channel.provider_service
  end

  def participants
    Array(params[:participants]).map(&:to_s).reject(&:blank?)
  end

  def ensure_group_conversation
    render json: { error: 'Conversation is not a group' }, status: :not_found unless @conversation.group?
  end

  def ensure_session_group_admin
    render json: { error: 'Connected session must be a group admin' }, status: :forbidden unless @conversation.group_session_admin?
  end

  def provider_error(response, fallback)
    response.parsed_response.try(:[], 'error') || fallback
  end
end
