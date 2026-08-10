class Whatsapp::IncomingMessageUnoapiService < Whatsapp::IncomingMessageWhatsappCloudService
  def perform
    log_catalog_event('unoapi_catalog_received', raw_catalog_diagnostics) if catalog_message?
    super
    log_catalog_event('unoapi_catalog_persisted', persisted_catalog_diagnostics) if catalog_message? && @message&.persisted?
  end

  private

  def processed_params
    @processed_params ||= begin
      value = Whatsapp::Unoapi::WebhookPayloadExtractor.new(params: params).perform.value
      catalog_message_from(value) ? value.deep_dup.tap { |payload| ensure_catalog_contact(payload) } : value
    end
  end

  def ensure_catalog_contact(payload)
    return if payload[:contacts].present?

    message = first_payload_message(payload)
    identifier = catalog_contact_identifier(payload, message)
    return if identifier.blank?

    payload[:contacts] = [catalog_contact_payload(payload, message, identifier)]
  end

  def first_payload_message(payload)
    Array(payload[:message_echoes]).first || Array(payload[:messages]).first
  end

  def catalog_contact_identifier(payload, message)
    keys = payload[:message_echoes].present? ? %i[to_parent_user_id to_user_id to] : %i[from_parent_user_id from_user_id from]
    keys.filter_map { |key| message[key].presence }.first
  end

  def catalog_contact_payload(payload, message, identifier)
    echo = payload[:message_echoes].present?
    {
      user_id: message[echo ? :to_user_id : :from_user_id].presence,
      parent_user_id: message[echo ? :to_parent_user_id : :from_parent_user_id].presence,
      wa_id: message[echo ? :to : :from].presence,
      profile: { name: identifier }
    }.compact
  end

  def message_content(message)
    return catalog_normalization[:content] if catalog_message?
    return interactive_normalization[:content] if interactive_normalization

    super
  end

  def message_content_attributes(message)
    attributes = super
    return attributes.merge(catalog_normalization[:content_attributes]) if catalog_message?
    return attributes.merge(interactive_normalization[:content_attributes]) if interactive_normalization

    attributes
  end

  def whatsapp_message_content_type(message)
    return catalog_normalization[:content_type] if catalog_message? && catalog_normalization[:content_type].present?
    return interactive_normalization[:content_type] if interactive_normalization

    super
  end

  def attach_files
    return if catalog_message?

    super
  end

  def reconcile_existing_message(source_id) # rubocop:disable Metrics/CyclomaticComplexity
    return super unless catalog_message? || interactive_normalization
    return false unless find_message_by_source_id(source_id)

    update_message_with_status(@message, status: 'delivered') if outgoing_echo
    normalization = catalog_message? ? catalog_normalization : interactive_normalization
    @message.assign_attributes(
      content: normalization[:content],
      content_type: normalization[:content_type].presence || @message.content_type,
      content_attributes: @message.content_attributes.to_h.merge(normalization[:content_attributes])
    )
    @message.save! if @message.changed?
    true
  end

  def catalog_message?
    catalog_message_from(processed_params)
  end

  def catalog_message_from(payload)
    message = Array(payload&.dig(:message_echoes)).first || Array(payload&.dig(:messages)).first
    Whatsapp::Unoapi::CatalogMessageNormalizer::CATALOG_TYPES.include?(message&.dig(:type).to_s)
  end

  def catalog_normalization
    @catalog_normalization ||= Whatsapp::Unoapi::CatalogMessageNormalizer.new(message: messages_data.first).perform.tap do |result|
      log_catalog_event('unoapi_catalog_normalized', result[:diagnostics])
    end
  end

  def create_regular_message(message)
    super
    preserve_interactive_reply_reference(message)
  end

  def preserve_interactive_reply_reference(message)
    return unless interactive_normalization
    return unless %w[button_reply list_reply].include?(message.dig(:interactive, :type).to_s)

    external_id = message.dig(:context, :id).presence || message.dig(:context, :message_id).presence
    return if external_id.blank? || @message.content_attributes['in_reply_to_external_id'].present?

    attributes = @message.content_attributes.to_h.merge('in_reply_to_external_id' => external_id)
    @message.update_column(:content_attributes, attributes) # rubocop:disable Rails/SkipsModelValidations
  end

  def interactive_normalization
    return @interactive_normalization if defined?(@interactive_normalization)

    @interactive_normalization = Whatsapp::Unoapi::InteractiveMessageNormalizer.new(message: messages_data.first).perform
  end

  def raw_catalog_diagnostics
    message = messages_data.first
    catalog = message[message[:type]].to_h.with_indifferent_access
    {
      source_id: message[:id],
      phone_number_id: processed_params.dig(:metadata, :phone_number_id),
      message_type: message[:type],
      order_id: catalog[:order_id],
      resolution_status: catalog[:resolution_status],
      item_count: catalog[:item_count].presence || Array(catalog[:items]).size
    }.compact
  end

  def persisted_catalog_diagnostics
    catalog_normalization[:diagnostics].merge(
      phone_number_id: processed_params.dig(:metadata, :phone_number_id),
      chatwoot_message_id: @message.id,
      conversation_id: @message.conversation_id
    ).compact
  end

  def log_catalog_event(event, diagnostics)
    Whatsapp::Unoapi::CatalogEventLogger.log(event, diagnostics)
  end

  def download_attachment_file(attachment_payload)
    downloaded_file = super
    return if downloaded_file.blank?

    Whatsapp::Unoapi::AudioTranscoder.new(downloaded_file).perform
  end
end
