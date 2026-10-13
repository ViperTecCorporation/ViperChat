module GoogleConcern
  extend ActiveSupport::Concern

  def google_client
    app_id = GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)
    app_secret = GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil)

    ::OAuth2::Client.new(app_id, app_secret, {
                           site: 'https://oauth2.googleapis.com',
                           authorize_url: 'https://accounts.google.com/o/oauth2/auth',
                           token_url: 'https://accounts.google.com/o/oauth2/token'
                         })
  end

  private

  def scope
    return "email profile #{Google::GmailClient::SCOPES.join(' ')}" if gmail_api_default?

    'email profile https://mail.google.com/'
  end

  def gmail_api_default?
    return @gmail_api_default unless @gmail_api_default.nil?

    @gmail_api_default = ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load('GOOGLE_GMAIL_API_ENABLED', false))
  end
end
