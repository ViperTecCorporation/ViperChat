class Whatsapp::UnoapiWebhookSetupService
  def perform(whatsapp_channel)
    if whatsapp_channel.provider_config['disconnect']
      whatsapp_channel.provider_config.delete('connect')
      whatsapp_channel.provider_config.delete('disconnect')
      return disconnect(whatsapp_channel)
    end
    return true unless whatsapp_channel.provider_config['connect']

    whatsapp_channel.provider_config.delete('connect')
    whatsapp_channel.provider_config.delete('disconnect')
    connect(whatsapp_channel)
  end

  private

  def disconnect(whatsapp_channel)
    phone_number = whatsapp_channel.provider_config['business_account_id']
    Rails.logger.debug { "Disconnecting #{phone_number} from unoapi" }
    response = HTTParty.post("#{url(whatsapp_channel)}/deregister", headers: headers(whatsapp_channel))
    if response.success?
      true
    else
      whatsapp_channel.errors.add(:provider_config, response.body)
      false
    end
  end

  def connect(whatsapp_channel)
    phone_number = whatsapp_channel.provider_config['business_account_id']
    url = url(whatsapp_channel)
    Rails.logger.debug { "Connecting #{phone_number} from unoapi with url #{url}" }
    body = params(whatsapp_channel, phone_number)
    response = HTTParty.post("#{url}/register", headers: headers(whatsapp_channel), body: body.to_json)
    Rails.logger.debug { "Response #{response}" }
    if response.success?
      connected = send_message(whatsapp_channel)
      contact_sync_enabled = connected && whatsapp_channel.contact_sync_enabled?
      Whatsapp::Unoapi::ContactSync::ConnectionCheckJob.set(wait: 5.seconds).perform_later(whatsapp_channel.id) if contact_sync_enabled
      return connected
    end

    whatsapp_channel.errors.add(:provider_config, response.body)
    true
  end

  def send_message(whatsapp_channel)
    phone_number = whatsapp_channel.provider_config['business_account_id']
    Rails.logger.debug { "Save #{phone_number} configuration unoapi" }
    body = {
      messaging_product: :whatsapp,
      to: phone_number,
      type: :text,
      text: {
        body: 'connect...'
      }
    }
    Rails.logger.debug { "Sending message to #{phone_number} unoapi" }
    response = HTTParty.post("#{url(whatsapp_channel)}/messages", headers: headers(whatsapp_channel), body: body.to_json)
    Rails.logger.debug { "Response #{response}" }
    return true if response.success?

    whatsapp_channel.errors.add(:provider_config, response.body)
    false
  end

  def url(whatsapp_channel)
    "#{whatsapp_channel.unoapi_api_url}/v15.0/#{whatsapp_channel.provider_config['business_account_id']}"
  end

  def headers(whatsapp_channel)
    {
      Authorization: whatsapp_channel.unoapi_auth_token,
      'Content-Type': 'application/json'
    }
  end

  # rubocop:disable Metrics/MethodLength
  def params(whatsapp_channel, phone_number)
    provider_config = whatsapp_channel.provider_config
    callback_url = webhook_callback_url(phone_number)
    send_transcribe_audio = provider_config.key?('send_transcribe_audio') ? provider_config['send_transcribe_audio'] : true
    connection_type = provider_config['connection_type']
    connection_type = 'qrcode' unless %w[qrcode pairing_code].include?(connection_type)
    label = "#{whatsapp_channel.inbox.name} - account #{whatsapp_channel.account_id}"
    default_webhook = {
      sendNewMessages: true,
      id: 'default',
      urlAbsolute: callback_url,
      token: provider_config['webhook_verify_token'],
      header: :Authorization,
      sendGroupMessages: true,
      sendNewsletterMessages: false,
      sendOutgoingMessages: true,
      sendIncomingMessages: true,
      sendUpdateMessages: true,
      sendTranscribeAudio: send_transcribe_audio,
      addToBlackListOnOutgoingMessageWithTtl: '',
      timeoutMs: 360_000
    }

    {
      autoConnect: true,
      connectionType: connection_type,
      useRedis: true,
      useS3: true,
      ignoreGroupMessages: provider_config['ignore_group_messages'],
      ignoreNewsletterMessages: provider_config['ignore_newsletter_messages'],
      ignoreGroupIndividualReceipts: provider_config['ignore_group_individual_receipts'],
      groupOnlyDeliveredStatus: provider_config['group_only_delivered_status'],
      ignoreBroadcastStatuses: provider_config['ignore_broadcast_statuses'],
      ignoreBroadcastMessages: provider_config['ignore_broadcast_messages'],
      ignoreHistoryMessages: provider_config['ignore_history_messages'],
      historyMaxAgeDays: provider_config.fetch('history_max_age_days', 7).to_i.clamp(1, 3650),
      ignoreOwnMessages: provider_config['ignore_own_messages'],
      ignoreYourselfMessages: provider_config['ignore_yourself_messages'],
      sendConnectionStatus: provider_config['send_connection_status'],
      markOnlineOnConnect: provider_config.fetch('mark_online_on_connect', false),
      notifyFailedMessages: provider_config['notify_failed_messages'],
      composingMessage: provider_config['composing_message'],
      sendTranscribeAudio: send_transcribe_audio,
      readOnReceipt: provider_config['read_on_receipt'],
      readOnReply: provider_config.fetch('read_on_reply', true),
      openaiApiKey: '',
      openaiApiTranscribeModel: 'whisper-1',
      groqApiKey: provider_config['groq_api_key'],
      groqApiTranscribeModel: 'whisper-large-v3',
      groqApiBaseUrl: 'https://api.groq.com/openai/v1',
      label: label,
      webhooks: merged_webhooks(whatsapp_channel, default_webhook),
      sendReactionAsReply: provider_config['send_reaction_as_reply'],
      sendProfilePicture: provider_config['send_profile_picture'],
      authToken: whatsapp_channel.unoapi_auth_token,
    }
  end
  # rubocop:enable Metrics/MethodLength

  def merged_webhooks(whatsapp_channel, default_webhook)
    existing_webhooks = fetch_existing_webhooks(whatsapp_channel)
    additional_webhooks = existing_webhooks.reject { |webhook| webhook['id'].to_s == 'default' }

    [default_webhook, *additional_webhooks]
  end

  def fetch_existing_webhooks(whatsapp_channel)
    response = HTTParty.get(url(whatsapp_channel), headers: headers(whatsapp_channel))
    return [] unless response.success?

    config = response.parsed_response
    config = JSON.parse(response.body) unless config.is_a?(Hash)
    Array(config['webhooks'])
  rescue StandardError => e
    Rails.logger.warn("[UNOAPI] Could not load existing webhooks before register: #{e.class}")
    []
  end

  def webhook_callback_url(phone_number)
    "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/whatsapp/#{phone_number}"
  end
end
