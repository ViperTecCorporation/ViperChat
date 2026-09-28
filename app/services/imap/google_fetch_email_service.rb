class Imap::GoogleFetchEmailService < Imap::BaseFetchEmailService
  def fetch_emails
    return if channel.provider_config['access_token'].blank?

    fetch_mail_for_channel
  end

  private

  def header_fetch_attributes
    super + ['INTERNALDATE']
  end

  def build_message_id_entry(data)
    cutoff = channel.provider_config.to_h['receive_since']
    return if cutoff.present? && data.attr.fetch('INTERNALDATE').to_time < Time.iso8601(cutoff)

    super
  end

  def authentication_type
    'XOAUTH2'
  end

  def imap_password
    Google::RefreshOauthTokenService.new(channel: channel).access_token
  end
end
