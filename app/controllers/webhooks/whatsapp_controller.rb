class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :verify_webhook_authentication!, only: :process_payload

  def process_payload
    return head :unauthorized if whatsapp_channel.blank? && url_channels.many?

    if inactive_whatsapp_number?
      Rails.logger.warn("Rejected webhook for inactive WhatsApp number: #{params[:phone_number]}")
      render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity
      return
    end

    payload = params.to_unsafe_hash.except('whatsapp_channel_id', 'whatsapp_provider')
    if whatsapp_channel
      payload['whatsapp_provider'] = whatsapp_channel.provider
      payload['whatsapp_channel_id'] = whatsapp_channel.id if whatsapp_channel.provider == 'unoapi'
    end
    Webhooks::WhatsappEventsJob.perform_later(payload)
    head :ok
  end

  private

  def verify_webhook_authentication!
    # An UnoAPI URL fallback is routing evidence, not proof of authentication.
    unoapi_route = whatsapp_channel&.provider == 'unoapi' || (whatsapp_channel.blank? && url_channels.any? { |channel| channel.provider == 'unoapi' })
    return head :unauthorized if unoapi_route && authenticated_unoapi_channel.blank?

    verify_meta_signature!
  end

  def valid_token?(token)
    return false if token.blank?

    url_channels.any? do |channel|
      expected = channel.provider_config['webhook_verify_token']
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, token)
    end
  end

  def meta_app_secrets
    [
      *channel_meta_app_secrets(whatsapp_channel),
      GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    ]
  end

  def whatsapp_channel
    @whatsapp_channel ||= authenticated_unoapi_channel || whatsapp_business_payload_channel || url_channel
  end

  def url_channel
    return url_channels.first if url_channels.one?
    return if params.dig(:entry, 0, :changes, 0, :value, :metadata).present?
    return unless params[:object] == 'whatsapp_business_account' && request.headers[META_SIGNATURE_HEADER].present?

    url_channels.find { |channel| channel.provider == 'whatsapp_cloud' }
  end

  def url_channels
    @url_channels ||= Whatsapp::ChannelPhoneIdentity.channels(params[:phone_number]).to_a
  end

  def authenticated_unoapi_channel
    authorization = request.headers['Authorization'].to_s.delete_prefix('Bearer ')
    return if authorization.blank?

    matches = url_channels.select do |channel|
      expected = channel.provider_config['webhook_verify_token']
      channel.provider == 'unoapi' && expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, authorization)
    end
    matches.first if matches.one?
  end

  def meta_signature_verification_required?
    return true if whatsapp_channel.blank?
    return false unless whatsapp_channel.provider == 'whatsapp_cloud'
    return true if Whatsapp::WebhookEnvelope.units(params.to_unsafe_h).any? do |unit|
      Whatsapp::WebhookEnvelope.administrative?(unit.dig(:entry, 0, :changes, 0, :field))
    end
    return true if channel_meta_app_secrets(whatsapp_channel).present?

    whatsapp_channel.provider_config['source'] == 'embedded_signup'
  end

  def whatsapp_business_payload_channel
    return unless params[:object] == 'whatsapp_business_account'

    metadata = params.dig(:entry, 0, :changes, 0, :value, :metadata)
    return if metadata.blank?

    phone_number = normalized_phone_number(metadata[:display_phone_number])
    phone_number_id = metadata[:phone_number_id]
    channel = Whatsapp::ChannelPhoneIdentity.channels(phone_number).where(provider: 'whatsapp_cloud')
                                            .find_by("provider_config->>'phone_number_id' = ?", phone_number_id.to_s)

    return channel if channel && channel.provider_config['phone_number_id'] == phone_number_id
  end

  def normalized_phone_number(phone_number)
    return if phone_number.blank?

    phone_number = phone_number.to_s
    phone_number.start_with?('+') ? phone_number : "+#{phone_number}"
  end

  def inactive_whatsapp_number?
    phone_number = params[:phone_number]
    return false if phone_number.blank?

    inactive_numbers = GlobalConfig.get_value('INACTIVE_WHATSAPP_NUMBERS').to_s
    return false if inactive_numbers.blank?

    inactive_numbers_array = inactive_numbers.split(',').map(&:strip)
    inactive_numbers_array.include?(phone_number)
  end
end
