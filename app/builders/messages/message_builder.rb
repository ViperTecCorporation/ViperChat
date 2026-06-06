class Messages::MessageBuilder
  include ::FileTypeHelper
  include ::EmailHelper
  include ::DataHelper

  attr_reader :message

  def initialize(user, conversation, params)
    @params = params
    @private = params[:private] || false
    @conversation = conversation
    @user = user
    @account = conversation.account
    @message_type = params[:message_type] || 'outgoing'
    @attachments = params[:attachments]
    @is_voice_message = ActiveModel::Type::Boolean.new.cast(params[:is_voice_message])
    @automation_rule = content_attributes&.dig(:automation_rule_id)
    return unless params.instance_of?(ActionController::Parameters)

    @in_reply_to = content_attributes&.dig(:in_reply_to)
    @items = content_attributes&.dig(:items)
  end

  def perform
    if split_attachments_per_message?
      build_multiple_attachment_messages
    else
      @message = @conversation.messages.build(message_params)
      process_attachments
      process_contact_attachments
      process_emails
      # When the message has no quoted content, it will just be rendered as a regular message
      # The frontend is equipped to handle this case
      process_email_content
      @message.save!
      update_sticker_last_used
      @message
    end
  end

  private

  # Extracts content attributes from the given params.
  # - Converts ActionController::Parameters to a regular hash if needed.
  # - Attempts to parse a JSON string if content is a string.
  # - Returns an empty hash if content is not present, if there's a parsing error, or if it's an unexpected type.
  def content_attributes
    params = convert_to_hash(@params)
    content_attributes = params.fetch(:content_attributes, {})

    return safe_parse_json(content_attributes) if content_attributes.is_a?(String)
    return content_attributes if content_attributes.is_a?(Hash)

    {}
  end

  def process_attachments
    return if @attachments.blank?

    @attachments.each do |uploaded_attachment|
      attachment = @message.attachments.build(
        account_id: @message.account_id,
        file: uploaded_attachment
      )

      attachment.file_type = attachment_file_type(uploaded_attachment)
      tag_voice_message(attachment)
    end
  end

  def attachment_file_type(uploaded_attachment)
    if uploaded_attachment.is_a?(String)
      file_type_by_signed_id(uploaded_attachment)
    else
      file_type(uploaded_attachment&.content_type)
    end
  end

  def tag_voice_message(attachment)
    return unless @is_voice_message && attachment.file_type == 'audio'

    attachment.meta = (attachment.meta || {}).merge('is_voice_message' => true)
  end

  def process_contact_attachments
    return if contact_attachments.blank?

    contact_attachments.each do |contact|
      @message.attachments.build(
        account_id: @message.account_id,
        file_type: :contact,
        fallback_title: contact[:phone_number].to_s,
        meta: {
          formatted_name: contact[:formatted_name].to_s,
          first_name: contact[:first_name].to_s,
          last_name: contact[:last_name].to_s,
          email: contact[:email].to_s
        }.compact_blank
      )
    end
  end

  def split_attachments_per_message?
    return false if @attachments.blank?

    # For WhatsApp / NotificaMe we want one attachment per message
    whatsapp_or_notificame_inbox = @conversation.inbox&.whatsapp? || @conversation.inbox&.notifica_me?
    whatsapp_or_notificame_inbox && @attachments.size > 1
  end

  def build_multiple_attachment_messages
    created_messages = []

    @attachments.each_with_index do |uploaded_attachment, index|
      # For the first attachment keep the original content, for subsequent ones we can omit content
      content_for_message = index.zero? ? @params[:content] : nil

      @message = @conversation.messages.build(message_params.merge(content: content_for_message))

      # Temporarily set @attachments so that process_attachments only attaches the current file
      original_attachments = @attachments
      @attachments = [uploaded_attachment]

      process_attachments
      process_contact_attachments
      process_emails
      process_email_content

      @message.save!
      update_sticker_last_used
      created_messages << @message

      # Restore full attachments list for next iteration
      @attachments = original_attachments
    end

    # Return the first created message as the primary response
    @message = created_messages.first
    @message
  end

  def update_sticker_last_used
    sticker_id = content_attributes&.[]('sticker_id')
    return if sticker_id.blank?

    Rails.logger.info("[WhatsappStickers] update_last_used sticker_id=#{sticker_id} inbox_id=#{@conversation.inbox_id}")
    WhatsappSticker.where(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      id: sticker_id
    ).update_all(last_used_at: Time.current)
  end

  def process_emails
    return unless @conversation.inbox&.inbox_type == 'Email'

    cc_emails = process_email_string(@params[:cc_emails])
    bcc_emails = process_email_string(@params[:bcc_emails])
    to_emails = process_email_string(@params[:to_emails])

    all_email_addresses = cc_emails + bcc_emails + to_emails
    validate_email_addresses(all_email_addresses)

    @message.content_attributes[:cc_emails] = cc_emails
    @message.content_attributes[:bcc_emails] = bcc_emails
    @message.content_attributes[:to_emails] = to_emails
  end

  def process_email_content
    return unless should_process_email_content?

    @message.content_attributes ||= {}
    email_attributes = build_email_attributes
    @message.content_attributes[:email] = email_attributes
  end

  def process_email_string(email_string)
    return [] if email_string.blank?

    email_string.gsub(/\s+/, '').split(',')
  end

  def message_type
    if @conversation.inbox.channel_type != 'Channel::Api' && @message_type == 'incoming' && !@private
      raise StandardError, 'Incoming messages are only allowed in Api inboxes'
    end

    @message_type
  end

  def sender
    message_type == 'outgoing' ? (message_sender || @user) : @conversation.contact
  end

  def external_created_at
    @params[:external_created_at].present? ? { external_created_at: @params[:external_created_at] } : {}
  end

  def automation_rule_id
    @automation_rule.present? ? { content_attributes: { automation_rule_id: @automation_rule } } : {}
  end

  def campaign_id
    @params[:campaign_id].present? ? { additional_attributes: { campaign_id: @params[:campaign_id] } } : {}
  end

  def template_params
    @params[:template_params].present? ? { additional_attributes: { template_params: JSON.parse(@params[:template_params].to_json) } } : {}
  end

  def message_sender
    return if @params[:sender_type] != 'AgentBot'

    AgentBot.where(account_id: [nil, @conversation.account.id]).find_by(id: @params[:sender_id])
  end

  def status_param
    return { status: :read } if internal_chat?

    @params[:status] = :progress if params_status_progress?
    @params[:status].present? ? { status: @params[:status] } : {}
  end

  def source_id_param
    @params[:source_id].present? ? { source_id: @params[:source_id] } : {}
  end

  def internal_chat?
    @conversation.inbox&.internal_chat?
  end

  def message_params
    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: message_type,
      content: @params[:content],
      private: @private,
      sender: sender,
      content_type: @params[:content_type],
      content_attributes: content_attributes.presence,
      items: @items,
      in_reply_to: @in_reply_to,
      echo_id: @params[:echo_id],
    }.merge(external_created_at)
      .merge(automation_rule_id)
      .merge(campaign_id)
      .merge(template_params)
      .merge(status_param)
      .merge(source_id_param)
  end

  def params_status_progress?
    @params[:status].blank? && @message_type == 'outgoing' && !@private && @params[:action] == 'create' && (@conversation.inbox&.whatsapp? || @conversation.inbox&.notifica_me?)
  end

  def email_inbox?
    @conversation.inbox&.inbox_type == 'Email'
  end

  def should_process_email_content?
    email_inbox? && !@private && @message.content.present?
  end

  def build_email_attributes
    email_attributes = ensure_indifferent_access(@message.content_attributes[:email] || {})
    normalized_content = normalize_email_body(@message.content)

    # Process liquid templates in normalized content with code block protection
    processed_content = process_liquid_in_email_body(normalized_content)

    # Use custom HTML content if provided, otherwise generate from message content
    email_attributes[:html_content] = if custom_email_content_provided?
                                        build_custom_html_content
                                      else
                                        build_html_content(processed_content)
                                      end

    email_attributes[:text_content] = build_text_content(processed_content)
    email_attributes
  end

  def build_html_content(normalized_content)
    html_content = ensure_indifferent_access(@message.content_attributes.dig(:email, :html_content) || {})
    rendered_html = render_email_html(normalized_content)
    html_content[:full] = rendered_html
    html_content[:reply] = rendered_html
    html_content
  end

  def build_text_content(normalized_content)
    text_content = ensure_indifferent_access(@message.content_attributes.dig(:email, :text_content) || {})
    text_content[:full] = normalized_content
    text_content[:reply] = normalized_content
    text_content
  end

  def custom_email_content_provided?
    @params[:email_html_content].present?
  end

  def build_custom_html_content
    html_content = ensure_indifferent_access(@message.content_attributes.dig(:email, :html_content) || {})

    html_content[:full] = @params[:email_html_content]
    html_content[:reply] = @params[:email_html_content]

    html_content
  end

  def contact_attachments
    contacts = content_attributes[:contacts] || content_attributes['contacts']
    return [] unless contacts.is_a?(Array)

    contacts.filter_map do |contact|
      normalized_contact_attachment(contact)
    end
  end

  def normalized_contact_attachment(contact)
    contact = contact.with_indifferent_access
    formatted_name = contact[:formatted_name].presence ||
                     contact[:formattedName].presence ||
                     contact[:name].presence
    first_name = contact[:first_name].presence || contact[:firstName].presence
    last_name = contact[:last_name].presence || contact[:lastName].presence

    if formatted_name.blank? && (first_name.present? || last_name.present?)
      formatted_name = [first_name, last_name].compact.join(' ')
    end

    if first_name.blank? && formatted_name.present?
      name_parts = formatted_name.split
      first_name = name_parts.first
      last_name = name_parts.drop(1).join(' ').presence
    end

    phone_number = contact[:phone_number].presence
    phone_number ||= contact[:phoneNumber].presence
    email = contact[:email].presence
    return if formatted_name.blank? || (phone_number.blank? && email.blank?)

    {
      formatted_name: formatted_name,
      first_name: first_name.presence || formatted_name,
      last_name: last_name,
      phone_number: phone_number,
      email: email
    }
  end

  # Liquid processing methods for email content
  def process_liquid_in_email_body(content)
    return content if content.blank?
    return content unless should_process_liquid?

    # Protect code blocks from liquid processing
    modified_content = modified_liquid_content(content)
    template = Liquid::Template.parse(modified_content)
    template.render(drops_with_sender)
  rescue Liquid::Error
    content
  end

  def should_process_liquid?
    @message_type == 'outgoing' || @message_type == 'template'
  end

  def drops_with_sender
    message_drops(@conversation).merge({
                                         'agent' => UserDrop.new(sender)
                                       })
  end
end

Messages::MessageBuilder.prepend_mod_with('Messages::MessageBuilder')

