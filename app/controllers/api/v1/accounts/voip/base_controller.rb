class Api::V1::Accounts::Voip::BaseController < Api::V1::Accounts::BaseController
  before_action :require_membership
  rescue_from ArgumentError do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def require_membership
    raise Pundit::NotAuthorizedError unless Current.account_user
  end

  def directory_resolver(service)
    @directory_resolvers ||= {}
    @directory_resolvers[service.id] ||= ::Voip::DirectoryService.new(
      account: Current.account, user: Current.user, membership: Current.account_user, service: service
    )
  end

  def remote_identities(rows)
    groups = rows.group_by do |row|
      row.is_a?(VoipCall) ? row.voip_agent_extension.voip_service : row.voip_service
    end
    groups.each_with_object({}) do |(service, group), result|
      next unless service.available_to?(Current.account_user)

      addresses = group.map { |row| row.is_a?(VoipCall) ? row.remote_address : row.address }
      result[service.id] = directory_resolver(service).identities(addresses)
    end
  end

  def services
    VoipService.where(account: Current.account)
  end

  def membership
    return Current.account_user if params[:account_user_id].blank?

    check_admin_authorization?
    Current.account.account_users.find(params[:account_user_id])
  end

  def require_idle!(member)
    raise ArgumentError, 'voip_call_in_progress' if VoipAgentExtension.busy?(member)
  end

  def authorized_service!
    service = services.find(params[:service_id])
    raise Pundit::NotAuthorizedError unless service.available_to?(membership)

    service
  end
end
