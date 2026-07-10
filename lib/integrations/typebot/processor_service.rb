class Integrations::Typebot::ProcessorService < Integrations::BotProcessorService
  pattr_initialize [:event_name!, :hook!, :event_data!]

  private

  def get_response(_session_id, message_content)
    session_id = conversation.custom_attributes['typebot_session_id']
    typebot_messages = []
    client_side_actions = []
    input_data = nil

    if session_id.blank?
      start_response = start_chat
      if start_response && start_response['sessionId']
        session_id = start_response['sessionId']
        conversation.custom_attributes['typebot_session_id'] = session_id
        conversation.save!

        typebot_messages.concat(start_response['messages'] || [])
        client_side_actions.concat(start_response['clientSideActions'] || [])
        input_data = start_response['input']
      end
    end

    if session_id.present? && message_content.present?
      continue_response = continue_chat(session_id, message_content)
      if continue_response
        typebot_messages.concat(continue_response['messages'] || [])
        client_side_actions.concat(continue_response['clientSideActions'] || [])
        input_data = continue_response['input'] || input_data
      end
    end

    {
      messages: typebot_messages,
      client_side_actions: client_side_actions,
      input: input_data
    }
  rescue StandardError => e
    Rails.logger.error "Typebot Error (account-#{hook.account_id}, hook-#{hook.id}): #{e.message}"
    nil
  end

  def process_response(message, response)
    return if response.blank?

    (response[:messages] || []).each do |typebot_msg|
      content_params = generate_content_params(typebot_msg)
      create_conversation(message, content_params) if content_params.present?
    end

    input = response[:input]
    if input.present? && input['type']&.include?('choice') && input['options'].is_a?(Array)
      items = input['options'].map do |option|
        {
          title: option['value'] || option['label'] || option['id'],
          value: option['value'] || option['label'] || option['id']
        }
      end
      if items.present?
        create_conversation(message, {
          content: 'Select an option',
          content_type: 'input_select',
          content_attributes: { items: items }
        })
      end
    end

    should_handoff = false
    (response[:client_side_actions] || []).each do |action|
      should_handoff = true if action['type'] == 'chatwoot'
    end

    process_action(message, 'handoff') if should_handoff
  end

  def create_conversation(message, content_params)
    return if content_params.blank?

    conversation = message.conversation
    conversation.messages.create!(
      content_params.merge(
        {
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        }
      )
    )
  end

  def start_chat
    base_url = hook.settings['typebot_url'].to_s.strip.gsub(/\/$/, '')
    typebot_id = hook.settings['typebot_id'].to_s.strip
    url = "#{base_url}/api/v1/typebots/#{typebot_id}/startChat"

    prefilled_variables = {
      'name' => contact.name,
      'email' => contact.email,
      'phone_number' => contact.phone_number,
      'conversation_id' => conversation.display_id,
      'inbox_id' => conversation.inbox_id
    }.compact

    body = {
      prefilledVariables: prefilled_variables
    }

    response = HTTParty.post(
      url,
      headers: { 'Content-Type' => 'application/json' },
      body: body.to_json
    )

    if response.success?
      response.parsed_response
    else
      Rails.logger.warn "Typebot Start Chat failed: #{response.code} - #{response.body}"
      nil
    end
  end

  def continue_chat(session_id, message_content)
    base_url = hook.settings['typebot_url'].to_s.strip.gsub(/\/$/, '')
    url = "#{base_url}/api/v1/sessions/#{session_id}/continueChat"

    body = {
      message: message_content
    }

    response = HTTParty.post(
      url,
      headers: { 'Content-Type' => 'application/json' },
      body: body.to_json
    )

    if response.success?
      response.parsed_response
    else
      Rails.logger.warn "Typebot Continue Chat failed: #{response.code} - #{response.body}"
      nil
    end
  end

  def generate_content_params(typebot_msg)
    type = typebot_msg['type']
    case type
    when 'text'
      text = extract_text(typebot_msg)
      { content: text } if text.present?
    when 'image'
      url = extract_url(typebot_msg)
      { content: "![Image](#{url})" } if url.present?
    when 'video'
      url = extract_url(typebot_msg)
      { content: "[Video](#{url})" } if url.present?
    when 'audio'
      url = extract_url(typebot_msg)
      { content: "[Audio](#{url})" } if url.present?
    else
      url = extract_url(typebot_msg)
      if url.present?
        { content: "[Attachment](#{url})" }
      else
        text = extract_text(typebot_msg)
        { content: text } if text.present?
      end
    end
  end

  def extract_text(message)
    if message['content'].is_a?(Hash)
      message['content']['html'] || message['content']['text']
    elsif message['content'].is_a?(String)
      message['content']
    else
      message['text']
    end
  end

  def extract_url(message)
    if message['content'].is_a?(Hash)
      message['content']['url']
    elsif message['content'].is_a?(String)
      message['content']
    else
      message['url']
    end
  end

  def contact
    @contact ||= conversation.contact
  end
end
