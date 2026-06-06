module Whatsapp::IncomingMessageServiceHelpers
  def download_attachment_file(attachment_payload)
    Down.download(inbox.channel.media_url(attachment_payload[:id]), headers: inbox.channel.api_headers)
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    }
  end

  def processed_params
    @processed_params ||= params
  end

  def account
    @account ||= inbox.account
  end

  def message_type
    messages_data.first[:type]
  end

  def message_content(message)
    # TODO: map interactive messages back to button messages in chatwoot
    interactive_content = build_interactive_content(message)
    type_key = message_type.presence
    message.dig(:text, :body) ||
      message.dig(:button, :text) ||
      message.dig(:interactive, :button_reply, :title) ||
      message.dig(:interactive, :list_reply, :title) ||
      interactive_content ||
      contact_formatted_name(message[:name] || message['name']) ||
      (type_key ? message.dig(type_key.to_sym, :caption) : nil)
  end

  def contact_formatted_name(name_payload)
    name_info = (name_payload || {}).with_indifferent_access

    name_info[:formatted_name].presence ||
      name_info[:formattedName].presence ||
      [name_info[:first_name], name_info[:last_name]].compact.join(' ').presence ||
      [name_info[:firstName], name_info[:lastName]].compact.join(' ').presence
  end

  def build_interactive_content(message)
    interactive = message[:interactive]
    return if interactive.blank?
    interactive_type = interactive[:type].to_s
    return if interactive_type.blank?

    parts = []
    header_text = interactive.dig(:header, :text)
    body_text = interactive.dig(:body, :text)
    footer_text = interactive.dig(:footer, :text)

    parts << header_text if header_text.present?
    parts << body_text if body_text.present?
    parts << footer_text if footer_text.present?

    case interactive_type
    when 'button'
      buttons = interactive.dig(:action, :buttons) || []
      button_lines = buttons.filter_map do |button|
        case button[:type].to_s
        when 'reply'
          title = button.dig(:reply, :title) || button[:title]
          build_option_line(title, nil)
        when 'cta_url'
          title = button.dig(:url, :title) || button[:title]
          link = button.dig(:url, :link) || button[:link]
          build_cta_line(title, link)
        when 'cta_call'
          title = button.dig(:call, :title) || button[:title]
          phone = button.dig(:call, :phone_number) || button[:phone_number]
          build_cta_line(title, phone)
        when 'cta_copy'
          title = button.dig(:copy_code, :title) || button[:title]
          code = button.dig(:copy_code, :code) || button[:code]
          build_cta_line(title, code)
        end
      end
      parts << "Options:\n#{button_lines.join("\n")}" if button_lines.any?
    when 'list'
      action = interactive[:action] || {}
      button_text = action[:button]
      parts << "Button: #{button_text}" if button_text.present?

      sections = action[:sections] || []
      rows = sections.flat_map { |section| section[:rows] || [] }
      if rows.any?
        row_lines = rows.map do |row|
          title = row[:title].to_s
          title = "#{title} - #{row[:description]}" if row[:description].present?
          title = "#{title} (#{row[:id]})" if row[:id].present?
          title
        end
        parts << "Options:\n#{row_lines.join("\n")}"
      end
    when 'cta_url'
      cta = interactive.dig(:action, :cta_url) || interactive[:cta_url] || {}
      display_text = cta[:display_text] || interactive.dig(:action, :display_text)
      url = cta[:url] || interactive.dig(:action, :url)
      parts << "Button: #{display_text}" if display_text.present?
      parts << "URL: #{url}" if url.present?
    when 'flow'
      action = interactive[:action] || {}
      flow_cta = action[:flow_cta] || action[:button]
      flow_id = action[:flow_id] || action[:id]
      flow_name = action[:flow_name]
      flow_token = action[:flow_token]
      flow_screen = action.dig(:flow_action_payload, :screen)
      parts << "Button: #{flow_cta}" if flow_cta.present?
      parts << "Flow: #{flow_name}" if flow_name.present?
      parts << "Flow ID: #{flow_id}" if flow_id.present?
      parts << "Screen: #{flow_screen}" if flow_screen.present?
      parts << "Token: #{flow_token}" if flow_token.present?
    end

    parts.reject(&:blank?).join("\n")
  end

  def build_option_line(title, option_id)
    return if title.blank? && option_id.blank?

    line = title.to_s
    line = option_id.to_s if line.blank?
    line = "#{line} (#{option_id})" if option_id.present? && line != option_id
    line
  end

  def build_cta_line(title, value)
    return if title.blank? && value.blank?

    label = title.to_s
    return value.to_s if label.blank?
    return label if value.blank?

    "#{label} - #{value}"
  end

  def file_content_type(file_type)
    return :image if %w[image sticker].include?(file_type)
    return :audio if %w[audio voice].include?(file_type)
    return :video if ['video'].include?(file_type)
    return :location if ['location'].include?(file_type)
    return :contact if ['contacts'].include?(file_type)

    :file
  end

  def unprocessable_message_type?(message_type)
    message_type.blank? || %w[reaction ephemeral request_welcome unsupported].include?(message_type)
  end

  def brazil_phone_number?(phone_number)
    phone_number.match(/^55/)
  end

  # ref: https://github.com/chatwoot/chatwoot/issues/5840
  def normalised_brazil_mobile_number(phone_number)
    # DDD : Area codes in Brazil are popularly known as "DDD codes" (códigos DDD) or simply "DDD", from the initials of "direct distance dialing"
    # https://en.wikipedia.org/wiki/Telephone_numbers_in_Brazil
    ddd = phone_number[2, 2]
    # Remove country code and DDD to obtain the number
    number = phone_number[4, phone_number.length - 4]
    normalised_number = "55#{ddd}#{number}"
    # insert 9 to convert the number to the new mobile number format
    normalised_number = "55#{ddd}9#{number}" if %w[6 7 8 9].include?(number[0]) && normalised_number.length != 13
    normalised_number
  end

  def argentina_phone_number?(phone_number)
    phone_number.match(/^54/)
  end

  def normalised_argentina_mobil_number(phone_number)
    # Remove 9 before country code
    phone_number.sub(/^549/, '54')
  end

  def processed_waid(waid)
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(waid, :cloud)
  end

  def whatsapp_phone_number(identifier)
    identifier = identifier.to_s
    return if identifier.blank?
    return unless identifier.match?(/\A\d{1,15}\z/)

    identifier
  end

  def error_webhook_event?(message)
    message.key?('errors')
  end

  def log_error(message)
    Rails.logger.warn "Whatsapp Error: #{message['errors'][0]['title']} - contact: #{message['from']}"
  end

  def process_in_reply_to(message)
    @in_reply_to_external_id = message['context']&.[]('id')
  end

  def find_message_by_source_id(source_id)
    return unless source_id

    @message = Message.find_by(source_id: source_id)
  end

  def lock_message_source_id!
    return false if messages_data.blank?

    Whatsapp::MessageDedupLock.new(messages_data.first[:id]).acquire!
  end
end
