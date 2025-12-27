class Voice::Provider::Custom::TokenService
  pattr_initialize [:inbox!, :user!, :account!]

  def generate
    token, token_source = resolved_token_with_source
    Rails.logger.info(
      "VOICE_CUSTOM_TOKEN account_id=#{account.id} inbox_id=#{inbox.id} user_id=#{user.id} token_source=#{token_source} username=#{resolved_username}"
    )
    {
      provider: 'custom',
      account_id: account.id,
      token: token,
      webrtc: webrtc_config,
      transfer: transfer_config
    }.compact
  end

  private

  def webrtc_config
    {
      ws_url: config['webrtc_ws_url'],
      sip_domain: config['sip_domain'],
      sip_outbound_proxy: config['sip_outbound_proxy'],
      sip_transport: config['sip_transport'] || 'wss',
      username: resolved_username,
      display_name: user.display_name.presence || user.name
    }.compact
  end

  def transfer_config
    {
      mode: config['transfer_mode'] || 'sip_refer'
    }
  end

  def resolved_token_with_source
    member_token = inbox_member&.webrtc_jwt
    return [member_token, 'inbox_member'] if member_token.present?

    user_token = user_custom_attributes['webrtc_jwt']
    return [user_token, 'user_profile'] if user_token.present?

    return [nil, 'missing_secret'] if config['jwt_secret'].blank?

    [JWT.encode(token_payload, config['jwt_secret'], 'HS256'), 'generated']
  end

  def token_payload
    payload = {
      sub: user.id.to_s,
      email: user.email,
      account_id: account.id,
      name: user.name
    }
    ttl = config['jwt_ttl'].to_i
    payload[:exp] = Time.zone.now.to_i + ttl if ttl.positive?
    payload[:iss] = config['jwt_issuer'] if config['jwt_issuer'].present?
    payload[:aud] = config['jwt_audience'] if config['jwt_audience'].present?
    payload
  end

  def resolved_username
    inbox_member&.webrtc_username.presence ||
      user_custom_attributes['webrtc_username'].presence ||
      user.email
  end

  def user_custom_attributes
    user.custom_attributes || {}
  end

  def inbox_member
    @inbox_member ||= inbox.inbox_members.find_by(user_id: user.id)
  end

  def config
    @config ||= inbox.channel.provider_config_hash.with_indifferent_access
  end
end
