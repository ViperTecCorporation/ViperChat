class Api::V1::Accounts::Voip::ProfilesController < Api::V1::Accounts::Voip::BaseController
  def show
    member = membership
    render json: {
      services: services.order(:name).select { |service| service.available_to?(member) }.map(&:public_payload),
      bindings: VoipAgentExtension.where(account_user: member).includes(:voip_service).map(&:public_payload),
      account_user_id: member.id
    }
  end

  def update
    member = membership
    service = authorized_service!
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator? || service.allow_self_configuration?

    member.with_lock do
      require_idle!(member)
      binding = VoipAgentExtension.find_or_initialize_by(account_user: member, voip_service: service)
      binding.assign_attributes(params.require(:binding).permit(:extension, :auth_username))
      assign_password(binding)
      binding.save!
      render json: binding.public_payload
    end
  end

  def activate
    member = membership
    member.with_lock do
      require_idle!(member)
      scope = VoipAgentExtension.where(account_user: member)
      binding = scope.find(params[:binding_id]) if params[:binding_id].present?
      if binding
        raise Pundit::NotAuthorizedError unless binding.voip_service.available_to?(member)
        raise ArgumentError, 'voip_missing_credential' if binding.credentials['password'].blank?
      end
      scope.where(active: true).find_each { |row| row.update!(active: false) }
      binding&.update!(active: true)
      render json: { active_binding_id: binding&.id }
    end
  end

  private

  def assign_password(binding)
    values = binding.credentials
    incoming = params.require(:binding)
    values['password'] = incoming[:password] if incoming[:password].present?
    values.delete('password') if incoming[:clear_password] == true
    binding.credentials = values
  end
end
