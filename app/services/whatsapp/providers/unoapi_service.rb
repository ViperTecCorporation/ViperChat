require 'cgi'

class Whatsapp::Providers::UnoapiService < Whatsapp::Providers::WhatsappCloudService
  def send_message(phone_number, message)
    return super unless pix_payment_request?(message)

    send_pix_payment_request(phone_number, message)
  end

  def validate_provider_config?
    url = "#{business_account_path}/message_templates?access_token=#{ENV.fetch('UNOAPI_AUTH_TOKEN', whatsapp_channel.provider_config['api_key'])}"
    return Whatsapp::UnoapiWebhookSetupService.new.perform(whatsapp_channel) if HTTParty.get(url).success?
  end

  def group_participants(group_id)
    HTTParty.get("#{unoapi_group_path(group_id)}/participants", headers: api_headers)
  end

  def send_message_edit(phone_number, message, content)
    request_body = {
      messaging_product: 'whatsapp',
      recipient_type: recipient_type_for(message),
      to: phone_number,
      type: 'message_edit',
      context: { message_id: message.source_id },
      text: { body: content.to_s }
    }

    response = HTTParty.post(messages_path, headers: api_headers, body: request_body.to_json)
    return response.parsed_response.dig('messages', 0, 'id') if response.success? && response.parsed_response['error'].blank?

    Rails.logger.error(response.body)
    nil
  end

  def create_group(subject:, participants:, description: nil, join_approval_mode: nil)
    payload = {
      subject: subject,
      description: description,
      participants: participants,
      join_approval_mode: join_approval_mode
    }.compact

    HTTParty.post("#{unoapi_phone_path}/groups", headers: api_headers, body: payload.to_json)
  end

  def group_details(group_id)
    HTTParty.get(unoapi_group_path(group_id), headers: api_headers)
  end

  def update_group(group_id:, subject: nil, description: nil, picture_url: nil, announcement: nil, locked: nil, join_approval_mode: nil)
    payload = {
      subject: subject,
      description: description,
      picture: picture_url.present? ? { url: picture_url } : nil,
      announcement: announcement,
      locked: locked,
      join_approval_mode: join_approval_mode
    }.compact

    HTTParty.patch(unoapi_group_path(group_id), headers: api_headers, body: payload.to_json)
  end

  def leave_group(group_id)
    HTTParty.delete(unoapi_group_path(group_id), headers: api_headers)
  end

  def group_invite_link(group_id)
    HTTParty.get("#{unoapi_group_path(group_id)}/invite_link", headers: api_headers)
  end

  def reset_group_invite_link(group_id)
    HTTParty.post("#{unoapi_group_path(group_id)}/invite_link", headers: api_headers)
  end

  def add_group_participants(group_id:, participants:)
    HTTParty.post(
      "#{unoapi_group_path(group_id)}/participants",
      headers: api_headers,
      body: { participants: participants }.to_json
    )
  end

  def remove_group_participants(group_id:, participants:)
    HTTParty.delete(
      "#{unoapi_group_path(group_id)}/participants",
      headers: api_headers,
      body: { participants: participants }.to_json
    )
  end

  def update_group_participant_roles(group_id:, action:, participants:)
    HTTParty.patch(
      "#{unoapi_group_path(group_id)}/participants",
      headers: api_headers,
      body: { action: action, participants: participants }.to_json
    )
  end

  def group_join_requests(group_id)
    HTTParty.get("#{unoapi_group_path(group_id)}/join_requests", headers: api_headers)
  end

  def approve_group_join_requests(group_id:, participants:)
    HTTParty.post(
      "#{unoapi_group_path(group_id)}/join_requests",
      headers: api_headers,
      body: { participants: participants }.to_json
    )
  end

  def reject_group_join_requests(group_id:, participants:)
    HTTParty.delete(
      "#{unoapi_group_path(group_id)}/join_requests",
      headers: api_headers,
      body: { participants: participants }.to_json
    )
  end

  private

  def pix_payment_request?(message)
    message.content_attributes&.dig('whatsapp_interactive', 'type') == 'payment_request'
  end

  def send_pix_payment_request(phone_number, message)
    return fail_pix_payment_request(message, 'PIX payment requests are not supported in groups') if message.conversation.group?

    pix_key = whatsapp_channel.provider_config['pix_key'].to_s.strip
    pix_key_type = whatsapp_channel.provider_config['pix_key_type'].to_s.upcase
    unless pix_key.present? && pix_key_type.in?(Channel::Whatsapp::UNOAPI_PIX_KEY_TYPES)
      return fail_pix_payment_request(message, 'PIX key is not configured for this inbox')
    end

    request_body = {
      messaging_product: 'whatsapp',
      to: phone_number,
      type: 'interactive',
      interactive: {
        type: 'button',
        action: {
          buttons: [{
            type: 'payment_request',
            payment_setting: {
              type: 'pix_static_code',
              pix_static_code: {
                merchant_name: pix_merchant_name,
                key: pix_key,
                key_type: pix_key_type
              }
            }
          }]
        }
      }
    }

    response = HTTParty.post(messages_path, headers: api_headers, body: request_body.to_json)
    process_pix_payment_response(response, message)
  end

  def process_pix_payment_response(response, message)
    parsed_response = response.parsed_response
    status = parsed_response['statuses']&.first if parsed_response.is_a?(Hash)
    return process_response(response, message) if status.blank?

    unless response.success? && parsed_response['error'].blank?
      handle_error(response, message)
      return
    end

    normalized_status = status['status'].to_s == 'received' ? 'delivered' : status['status'].to_s
    message.update!(status: normalized_status) if normalized_status.in?(%w[sent delivered read])
    status['id']
  end

  def pix_merchant_name
    whatsapp_channel.inbox&.name.presence || whatsapp_channel.account.name
  end

  def fail_pix_payment_request(message, error)
    message.update!(status: :failed, external_error: error)
    nil
  end

  def unoapi_group_path(group_id)
    "#{unoapi_phone_path}/groups/#{CGI.escape(group_id.to_s)}"
  end

  def unoapi_phone_path
    uno_session_id = whatsapp_channel.provider_config['phone_number_id'].presence || whatsapp_channel.provider_config['business_account_id']
    "#{api_base_path}/v15.0/#{uno_session_id}"
  end
end
