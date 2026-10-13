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

  def find_or_create_inbox
    account
    if @history_options&.dig('gmail_transport') == 'api' && parsed_body['scope'].present?
      granted = parsed_body['scope'].split
      unless granted.include?('https://mail.google.com/') || (Google::GmailClient::SCOPES - granted).empty?
        raise 'Gmail read and send permissions must both be granted'
      end
    end
    super
  end

  def account_from_signed_id
    @history_options = Rails.application.message_verifier('gmail-history').verified(params[:state].to_s)
    return super unless @history_options

    Google::EmailHistory.validate!(@history_options['period']) if @history_options['period'].present?
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
      config = previous.merge(channel_email.provider_config.to_h.compact)
      apply_gmail_transport(config, previous)
      channel_email.update!(provider_config: config)
    end
    return if @history_options&.dig('period').blank?

    Google::EmailHistory.start!(channel_email, @history_options['period'], new_channel: @new_history_channel == true)
  end

  def apply_gmail_transport(config, previous)
    config['gmail_transport'] = @history_options&.fetch('gmail_transport', 'imap') || 'imap'
    config.delete('gmail_sync') if previous['gmail_transport'] != config['gmail_transport']
    config['receive_since'] ||= Time.current.utc.iso8601 if @new_history_channel && config['gmail_transport'] == 'api'
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
