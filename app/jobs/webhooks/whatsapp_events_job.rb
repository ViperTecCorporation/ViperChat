class Webhooks::WhatsappEventsJob < MutexApplicationJob
  queue_as :low
  retry_on ActiveRecord::RecordNotFound, wait: 30.seconds, attempts: 5
  # Retry budget (19 × 2s = 38s) must exceed the 30s lock TTL set in `perform`, otherwise
  # a webhook that arrives just after the lock is acquired can exhaust retries before the
  # holder finishes and silently drop its message.
  retry_on LockAcquisitionError, wait: 2.seconds, attempts: 20
  # Retry longer than the processing lease; conflicts must not discard the event.
  retry_on Whatsapp::MessageDedupLock::Busy, wait: 10.seconds, attempts: 40
  retry_on Whatsapp::UnifiedMessageIngestionService::Busy, wait: 10.seconds, attempts: 40

  def perform(params = {})
    params = params.with_indifferent_access
    return if dispatched_or_ignored?(params)

    channel = find_channel_from_whatsapp_business_payload(params)

    if channel_is_inactive?(channel)
      Rails.logger.warn("Inactive WhatsApp channel: #{channel&.phone_number || "unknown - #{params[:phone_number]}"}")
      return
    end

    sender_id = contact_sender_id(params)
    return process_events(channel, params) if sender_id.blank?

    # Album uploads arrive as separate concurrent webhooks. Serialize per (inbox, contact)
    # so the first webhook creates the conversation and the rest append to it.
    # 30s TTL covers the attachment download + transaction — the default 1s expires
    # mid-processing and lets a concurrent webhook re-acquire before the first commit.
    key = format(::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: sender_id)
    with_lock(key, 30.seconds) do
      process_events(channel, params)
    end
  end

  def process_events(channel, params)
    if message_echo_event?(params)
      handle_message_echo(channel, params)
    else
      handle_message_events(channel, params)
    end
  end

  # Detects if the webhook is an SMB message echo event (message sent from WhatsApp Business app)
  # This is part of WhatsApp coexistence feature where businesses can respond from both
  # Chatwoot and the WhatsApp Business app, with messages synced to Chatwoot.
  #
  # Regular message payload (field: "messages"):
  # {
  #   "entry": [{
  #     "changes": [{
  #       "field": "messages",
  #       "value": {
  #         "contacts": [{ "wa_id": "919745786257", "profile": { "name": "Customer" } }],
  #         "messages": [{ "from": "919745786257", "id": "wamid...", "text": { "body": "Hello" } }]
  #       }
  #     }]
  #   }]
  # }
  #
  # Echo message payload (field: "smb_message_echoes"):
  # {
  #   "entry": [{
  #     "changes": [{
  #       "field": "smb_message_echoes",
  #       "value": {
  #         "message_echoes": [{ "from": "971545296927", "to": "919745786257", "id": "wamid...", "text": { "body": "Hi" } }]
  #       }
  #     }]
  #   }]
  # }
  #
  # Key differences:
  # - field: "smb_message_echoes" instead of "messages"
  # - message_echoes[] instead of messages[]
  # - "from" is the business number, "to" is the contact (reversed from regular messages)
  # - No "contacts" array in echo payload
  def message_echo_event?(params)
    %w[smb_message_echoes message_echoes].include?(params.dig(:entry, 0, :changes, 0, :field))
  end

  def handle_message_echo(channel, params)
    service = channel.provider == 'unoapi' ? Whatsapp::IncomingMessageUnoapiService : Whatsapp::IncomingMessageWhatsappCloudService
    service.new(inbox: channel.inbox, params: params, outgoing_echo: true).perform
  end

  def handle_message_events(channel, params)
    case channel.provider
    when 'whatsapp_cloud'
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
    when 'unoapi'
      Whatsapp::IncomingMessageUnoapiService.new(inbox: channel.inbox, params: params).perform
    else
      Whatsapp::IncomingMessageService.new(inbox: channel.inbox, params: params).perform
    end
  end

  private

  def dispatched_or_ignored?(params)
    dispatch_batch(params) || ignore_group_event?(params) || dispatch_management(params)
  end

  def ignore_group_event?(params)
    channel = find_channel_from_whatsapp_business_payload(params)
    return false unless channel

    policy = Whatsapp::GroupEventPolicy.new(inbox: channel.inbox)
    value = params.dig(:entry, 0, :changes, 0, :value) || params
    policy.ignored?(value, field: params.dig(:entry, 0, :changes, 0, :field))
  end

  def dispatch_batch(params)
    units = Whatsapp::WebhookEnvelope.units(params)
    return false unless units.size > 1

    units.each { |unit| self.class.perform_later(unit) }
    true
  end

  def dispatch_management(params)
    return false if params[:whatsapp_provider].present? && params[:whatsapp_provider] != 'whatsapp_cloud'

    field = params.dig(:entry, 0, :changes, 0, :field)
    return false unless Whatsapp::WebhookEnvelope.administrative?(field)

    receipts = Whatsapp::ManagementWebhookService.new(params: params).perform
    return true unless field == 'group_settings_update'

    dispatch_group_settings(params, receipts)
  end

  def dispatch_group_settings(params, receipts)
    channel = find_channel_from_whatsapp_business_payload(params)
    return false unless channel&.provider == 'whatsapp_cloud'
    return true if receipts.empty? || channel_is_inactive?(channel)

    receipts.each do |receipt|
      receipt.with_lock do
        next if receipt.state == 'processed'

        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
        receipt.update!(state: 'processed')
      end
    end
    true
  end

  # Echo payloads reverse the fields — `from` is the business number and `to` is the contact.
  # Returns nil for status-only webhooks so they bypass the lock.
  def contact_sender_id(params)
    value = params.dig(:entry, 0, :changes, 0, :value) || params
    group = Array(value[:messages] || value[:message_echoes]).first.to_h[:group_id].presence || Array(value[:contacts]).first.to_h[:group_id]
    return "group:#{group}" if group.present?

    return contact_sender_id_from_message_echoes(value[:message_echoes]) if value[:message_echoes].present?

    contact_sender_id_from_messages(value[:messages], value[:contacts])
  end

  # Echo payloads are outbound messages from the WhatsApp Business app, so `to`
  # points to the contact. Prefer parent BSUID when present so payloads that have
  # both regular+parent BSUIDs serialize with parent-BSUID-only payloads.
  def contact_sender_id_from_message_echoes(message_echoes)
    message = message_echoes&.first
    return if message.blank?

    [message[:to_parent_user_id], message[:to_user_id], message[:to]].compact_blank.first
  end

  # Regular inbound payloads are sent by the contact, so `from` points to the
  # contact. Prefer parent BSUID when present so payloads that have both
  # regular+parent BSUIDs serialize with parent-BSUID-only payloads.
  def contact_sender_id_from_messages(messages, contacts)
    message = messages&.first
    return if message.blank?

    contact = contacts&.first || {}

    [
      message[:from_parent_user_id],
      contact[:parent_user_id],
      message[:from_user_id],
      contact[:user_id],
      message[:from]
    ].compact_blank.first
  end

  def channel_is_inactive?(channel)
    return true if channel.blank?
    # Only skip for embedded signup when reauth is required; manual flow uses API keys and should still receive webhooks
    return true if channel.reauthorization_required? && embedded_signup_channel?(channel)
    return true unless channel.account.active?

    false
  end

  def embedded_signup_channel?(channel)
    (channel.provider_config || {}).to_h['source'] == 'embedded_signup'
  end

  def find_channel_by_url_param(params)
    return unless params[:phone_number]

    scope = Channel::Whatsapp.where(phone_number: params[:phone_number])
    scope = scope.where(provider: params[:whatsapp_provider]) if params[:whatsapp_provider].present?
    channels = scope.limit(2).to_a
    channels.first if channels.one?
  end

  def find_channel_from_whatsapp_business_payload(params)
    return authenticated_channel(params) if params[:whatsapp_channel_id].present?

    # for the case where facebook cloud api support multiple numbers for a single app
    # https://github.com/chatwoot/chatwoot/issues/4712#issuecomment-1173838350
    # we will give priority to the phone_number in the payload
    if params[:object] == 'whatsapp_business_account'
      return get_channel_from_wb_payload(params) || fallback_channel_from_url_param(params)
    end

    find_channel_by_url_param(params)
  end

  def authenticated_channel(params)
    channel = Channel::Whatsapp.find_by(id: params[:whatsapp_channel_id])
    return channel unless params[:object] == 'whatsapp_business_account'

    metadata = wb_payload_metadata(params)
    return if channel.blank? || metadata.blank?
    return unless channel.provider_config['phone_number_id'].to_s == metadata[:phone_number_id].to_s

    channel
  end

  def get_channel_from_wb_payload(wb_params)
    metadata = wb_payload_metadata(wb_params)
    return if metadata.blank?

    phone_number = payload_phone_number(wb_params)
    phone_number_id = metadata[:phone_number_id]
    scope = Whatsapp::ChannelPhoneIdentity.channels(phone_number)
    scope = scope.where(provider: wb_params[:whatsapp_provider]) if wb_params[:whatsapp_provider].present?
    channels = scope.select do |candidate|
      candidate.provider_config['phone_number_id'].to_s == phone_number_id.to_s
    end
    # validate to ensure the phone number id matches the whatsapp channel
    channels.first if channels.one?
  end

  def fallback_channel_from_url_param(wb_params)
    # Some official Meta payloads can send a display_phone_number that is not identical to
    # the configured webhook URL number. If the payload number does not identify any local
    # channel, fall back to the verified URL param. If it identifies a channel but the
    # phone_number_id mismatches, do not fall back because that would route to the wrong inbox.
    return if wb_payload_metadata(wb_params).blank?

    payload_number = payload_phone_number(wb_params)
    return find_channel_by_url_param(wb_params) if payload_number.blank?
    return if Whatsapp::ChannelPhoneIdentity.channels(payload_number).exists?

    channel = find_channel_by_url_param(wb_params)
    channel if channel && channel.provider_config['phone_number_id'].to_s == wb_payload_metadata(wb_params)[:phone_number_id].to_s
  end

  def payload_phone_number(wb_params)
    display_phone_number = wb_payload_metadata(wb_params)&.dig(:display_phone_number)
    return if display_phone_number.blank?

    display_phone_number.to_s.start_with?('+') ? display_phone_number.to_s : "+#{display_phone_number}"
  end

  def wb_payload_metadata(wb_params)
    wb_params.dig(:entry, 0, :changes, 0, :value, :metadata)
  end
end
