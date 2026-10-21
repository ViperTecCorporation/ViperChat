class Api::V1::Accounts::Voip::CallsController < Api::V1::Accounts::Voip::BaseController
  def index
    scope = visible_calls.includes(voip_agent_extension: [:voip_service, :account_user])
    scope = filtered(scope)
    page = [params[:page].to_i, 1].max
    rows = scope.order(started_at: :desc, id: :desc).limit(5).offset((page - 1) * 5).to_a
    identities = remote_identities(rows)
    render json: { items: rows.map do |row|
      row.public_payload(remote_identity: identities.dig(row.voip_agent_extension.voip_service_id, row.remote_address))
    end,
                   total: scope.count, page: page, coverage: 'client_observed' }
  end

  def show
    render_call(visible_calls.find(params[:id]))
  end

  def create
    binding = VoipAgentExtension.where(account_user: Current.account_user, active: true).find(params[:binding_id])
    raise Pundit::NotAuthorizedError unless binding.voip_service.available_to?(Current.account_user)

    attributes = params.require(:call).permit(:client_call_id, :sip_call_id, :direction, :remote_address, :remote_name)
    call = ::Voip::CreateCallService.new(binding: binding, attributes: attributes).perform
    render_call(call, status: :created)
  end

  def observe
    call = own_calls.find(params[:id])
    attributes = params.require(:observation).permit(:event_id, :sequence, :state, :sip_code, :end_reason)
    raise ArgumentError, 'invalid_sip_code' if attributes[:sip_code].present? && !(100..699).cover?(attributes[:sip_code].to_i)
    raise ArgumentError, 'invalid_reason' if attributes[:end_reason].to_s.length > 128

    ::Voip::ObserveCallService.new(call: call, attributes: attributes).perform
    render_call(call.reload)
  end

  private

  def render_call(call, status: :ok)
    identity = remote_identities([call]).dig(call.voip_agent_extension.voip_service_id, call.remote_address)
    render json: call.public_payload(remote_identity: identity), status: status
  end

  def own_calls
    VoipCall.joins(:voip_agent_extension).where(account: Current.account, voip_agent_extensions: { account_user_id: Current.account_user.id })
  end

  def visible_calls
    Current.account_user.administrator? ? VoipCall.where(account: Current.account) : own_calls
  end

  def filtered(scope)
    scope = state_filter(scope)
    scope = scope.where(direction: params[:direction]) if params[:direction].present?
    scope = scope.where(voip_agent_extensions: { voip_service_id: params[:service_id] }).joins(:voip_agent_extension) if params[:service_id].present?
    scope = scope.where(local_agent_id: params[:agent_id]) if params[:agent_id].present?
    searched(date_filtered(scope))
  end

  def date_filtered(scope)
    scope = scope.where('started_at >= ?', Time.iso8601(params[:from])) if params[:from].present?
    scope = scope.where('started_at <= ?', Time.iso8601(params[:until])) if params[:until].present?
    scope
  end

  def state_filter(scope)
    if params[:state] == 'awaiting_confirmation'
      scope = scope.where(state: 'awaiting_confirmation').or(scope.where(state: VoipCall::LIVE_STATES).where('last_observed_at < ?', 90.seconds.ago))
    elsif params[:state].present?
      scope = scope.where(state: params[:state])
      scope = scope.where('last_observed_at >= ?', 90.seconds.ago) if VoipCall::LIVE_STATES.include?(params[:state])
    end
    scope
  end

  def searched(scope)
    return scope if params[:search].blank?

    query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)}%"
    scope = scope.joins(:voip_agent_extension)
    text_scope = scope.where("unaccent(coalesce(remote_name, '') || ' ' || remote_address || ' ' || voip_calls.local_extension) ILIKE unaccent(?)",
                             query)
    text_scope = identified_name_matches(scope, text_scope)
    return text_scope unless params[:search].match?(/\A[+\d\s().-]+\z/)

    digits = params[:search].gsub(/\D/, '')
    return text_scope if digits.empty?

    text_scope.or(scope.where("regexp_replace(remote_address, '[^0-9]', '', 'g') LIKE ?", "%#{digits}%"))
  end

  def identified_name_matches(scope, matches)
    services.each do |service|
      next unless service.available_to?(Current.account_user)

      matches = matches.or(directory_resolver(service).matching_calls(scope, params[:search].to_s.strip))
    end
    matches
  end
end
