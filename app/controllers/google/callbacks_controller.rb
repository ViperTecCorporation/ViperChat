class Google::CallbacksController < OauthCallbackController
  include GoogleConcern

  def find_channel_by_email
    # find by imap_login first, and then by email
    # this ensures the legacy users can migrate correctly even if inbox email address doesn't match
    imap_channel = Channel::Email.find_by(imap_login: users_data['email'], account: account)
    return imap_channel if imap_channel

    Channel::Email.find_by(email: users_data['email'], account: account)
  end

  private

  def account_from_signed_id
    @history_options = Rails.application.message_verifier('gmail-history').verified(params[:state].to_s)
    return super unless @history_options

    Google::EmailHistory.validate!(@history_options.fetch('period'))
    @return_to = @history_options['return_to']
    purpose = @return_to == 'onboarding' ? 'onboarding' : 'default'
    GlobalID::Locator.locate_signed(@history_options.fetch('account_state'), for: purpose) || raise('Invalid or expired state')
  end

  def update_channel(channel_email)
    # Resolve signed options before creating any import configuration.
    account
    channel_email.with_lock do
      previous = channel_email.provider_config.to_h
      super
      channel_email.update!(provider_config: previous.merge(channel_email.provider_config.to_h))
    end
    Google::EmailHistory.start!(channel_email, @history_options['period'], new_channel: @new_history_channel == true) if @history_options
  end

  def create_channel_with_inbox
    @new_history_channel = true
    super
  end

  def provider_name
    'google'
  end

  def imap_address
    'imap.gmail.com'
  end

  def oauth_client
    # from GoogleConcern
    google_client
  end
end
