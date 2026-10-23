class Api::V1::Accounts::Voip::ServicesController < Api::V1::Accounts::Voip::BaseController
  before_action :check_admin_authorization?

  def index
    rows = services.includes(voip_agent_extensions: { account_user: :user }).order(:name).map do |service|
      bindings = service.voip_agent_extensions.filter_map do |binding|
        next unless binding.account_user

        { id: binding.id, account_user_id: binding.account_user_id, extension: binding.extension,
          agent_name: binding.account_user.user.name, active: binding.active }
      end
      admin_payload(service).merge(bindings: bindings)
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
    render json: admin_payload(service), status: :created
  end

  def update
    service = services.find(params[:id])
    service.assign_attributes(service_params)
    assign_credentials(service)
    service.save!
    render json: admin_payload(service)
  end

  def destroy
    service = services.find(params[:id])
    service.update!(enabled: false)
    head :no_content
  end

  private

  def admin_payload(service)
    base = ENV.fetch('FRONTEND_URL', request.base_url).delete_suffix('/')
    service.admin_payload.merge(webhook_url: "#{base}/api/v1/accounts/#{service.account_id}/voip/services/#{service.id}/events")
  end

  def service_params
    params.require(:service).permit(:name, :wss_url, :sip_domain, :enabled, :allow_self_configuration,
                                    :transfer_enabled, :registration_expires, allowed_user_ids: [])
  end

  def assign_credentials(service)
    incoming = credential_params
    %w[stun_url turn_url].each do |field|
      value = incoming[field]
      raise ArgumentError, 'invalid_ice_url' if value.present? && !value.match?(/\A(?:stun|stuns|turn|turns):[^\s@]+\z/)
    end
    service.credentials = merge_credentials(service.credentials, incoming)
  end

  def credential_params
    params.require(:service).permit(:stun_url, :turn_url, :turn_username, :turn_password, :clear_turn_password,
                                    :integration_provider, :webhook_source_instance_id, :history_api_url, :history_company_id,
                                    :history_api_token, :clear_history_api_token, :reopen_on_incoming).to_h
  end

  def merge_credentials(existing, incoming)
    secrets = %w[turn_password ami_password history_api_token]
    values = existing.merge(incoming.except(*secrets, *secrets.map { |field| "clear_#{field}" }))
    secrets.each do |field|
      values[field] = incoming[field] if incoming[field].present?
      values.delete(field) if incoming["clear_#{field}"] == true
    end
    values
  end
end
