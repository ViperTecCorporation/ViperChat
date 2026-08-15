class Api::V1::Accounts::Conversations::DirectUploadsController < ActiveStorage::DirectUploadsController
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequestExceptionHandler
  include AccessTokenAuthHelper
  include EnsureCurrentAccountHelper

  # Direct uploads can be authenticated either with an API access token or the
  # Devise token headers used by the native app. Header-authenticated requests
  # are not vulnerable to cookie-based CSRF and the Capacitor WebView has a
  # local origin that intentionally differs from the remote installation.
  skip_before_action :verify_authenticity_token, if: :token_authenticated_request?

  around_action :handle_with_exception
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  before_action :current_account
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  before_action :conversation

  def create
    return if @conversation.nil? || @current_account.nil?

    super
  end

  private

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end

  def token_authenticated_request?
    authenticate_by_access_token? || devise_token_headers_present?
  end

  def devise_token_headers_present?
    request.headers['access-token'].present? && request.headers['client'].present? && request.headers['uid'].present?
  end

  def validate_token_api_access
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end

  def conversation
    @conversation ||= Current.account.conversations.find_by(display_id: params[:conversation_id])
  end
end
