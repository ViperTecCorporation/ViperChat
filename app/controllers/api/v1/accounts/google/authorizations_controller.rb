class Api::V1::Accounts::Google::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include GoogleConcern

  def create
    Google::EmailHistory.validate!(params[:history_period]) if params.key?(:history_period)
    redirect_url = google_client.auth_code.authorize_url(
      {
        redirect_uri: "#{base_url}/google/callback",
        scope: scope,
        response_type: 'code',
        prompt: 'consent', # the oauth flow does not return a refresh token, this is supposed to fix it
        access_type: 'offline', # the default is 'online'
        state: state,
        client_id: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)
      }
    )

    if redirect_url
      render json: { success: true, url: redirect_url }
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def state
    return super unless params.key?(:history_period)

    Rails.application.message_verifier('gmail-history').generate(
      { 'account_state' => super, 'period' => params[:history_period], 'return_to' => params[:return_to] }, expires_in: 15.minutes
    )
  end
end
