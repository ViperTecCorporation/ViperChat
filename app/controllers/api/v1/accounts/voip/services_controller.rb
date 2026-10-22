class Api::V1::Accounts::Voip::ServicesController < Api::V1::Accounts::Voip::BaseController
  before_action :check_admin_authorization?

  def index
    rows = services.includes(voip_agent_extensions: { account_user: :user }).order(:name).map do |service|
      bindings = service.voip_agent_extensions.filter_map do |binding|
        next unless binding.account_user

        { id: binding.id, account_user_id: binding.account_user_id, extension: binding.extension,
          agent_name: binding.account_user.user.name, active: binding.active }
      end
      service.admin_payload.merge(bindings: bindings)
    end
    render json: rows
  end

  def agents
    render json: Current.account.account_users.includes(:user).map { |row| { id: row.id, user_id: row.user_id, name: row.user.name } }
  end

  def create
    service = services.new(service_params)
    assign_credentials(service)
    service.save!
    render json: service.admin_payload, status: :created
  end

  def update
    service = services.find(params[:id])
    service.assign_attributes(service_params)
    assign_credentials(service)
    service.save!
    render json: service.admin_payload
  end

  def destroy
    service = services.find(params[:id])
    service.update!(enabled: false)
    head :no_content
  end

  private

  def service_params
    params.require(:service).permit(:name, :wss_url, :sip_domain, :enabled, :allow_self_configuration,
                                    :transfer_enabled, :registration_expires, allowed_user_ids: [])
  end

  def assign_credentials(service)
    incoming = params.require(:service).permit(:stun_url, :turn_url, :turn_username, :turn_password, :clear_turn_password).to_h
    %w[stun_url turn_url].each do |field|
      value = incoming[field]
      raise ArgumentError, 'invalid_ice_url' if value.present? && !value.match?(/\A(?:stun|stuns|turn|turns):[^\s@]+\z/)
    end
    values = service.credentials.merge(incoming.except('turn_password', 'clear_turn_password'))
    values['turn_password'] = incoming['turn_password'] if incoming['turn_password'].present?
    values.delete('turn_password') if incoming['clear_turn_password'] == true
    service.credentials = values
  end
end
