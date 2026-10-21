class Api::V1::Accounts::Voip::RegistrationsController < Api::V1::Accounts::Voip::BaseController
  def create
    response.headers['Cache-Control'] = 'no-store, private'
    response.headers['Pragma'] = 'no-cache'
    scope = VoipAgentExtension.where(account_user: Current.account_user)
    binding = params[:binding_id].present? ? scope.find(params[:binding_id]) : scope.find_by!(active: true)
    service = binding.voip_service
    raise Pundit::NotAuthorizedError unless service.available_to?(Current.account_user)
    raise ArgumentError, 'voip_missing_credential' if binding.credentials['password'].blank?

    render json: bootstrap(binding, service)
  end

  private

  def bootstrap(binding, service)
    {
      binding_id: binding.id, service_id: service.id, service_name: service.name, extension: binding.extension,
      username: binding.auth_username, password: binding.credentials['password'], wss_url: service.wss_url,
      sip_domain: service.sip_domain, registration_expires: service.registration_expires,
      transfer_enabled: service.transfer_enabled, ice_servers: service.ice_servers
    }
  end
end
