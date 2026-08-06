class Whatsapp::IncomingMessageUnoapiService < Whatsapp::IncomingMessageWhatsappCloudService
  def perform
    log_catalog_event('unoapi_catalog_received', raw_catalog_diagnostics) if catalog_message?
    super
    log_catalog_event('unoapi_catalog_persisted', persisted_catalog_diagnostics) if catalog_message? && @message&.persisted?
  end

  private

  def processed_params
    @processed_params ||= begin
      value = super.presence || params
      catalog_message_from(value) ? value.deep_dup.tap { |payload| ensure_catalog_contact(payload) } : value
    end
  end

  def ensure_catalog_contact(payload)
    return if payload[:contacts].present?

    message = payload[:messages].first
    identifier = message[:from_user_id].presence || message[:from].presence
    return if identifier.blank?

    payload[:contacts] = [{
      user_id: message[:from_user_id].presence,
      wa_id: message[:from].presence,
      profile: { name: identifier }
    }.compact]
  end

  def message_content(message)
    return super unless catalog_message?

    catalog_normalization[:content]
  end

  def message_content_attributes(message)
    attributes = super
    return attributes unless catalog_message?

    attributes.merge(catalog_normalization[:content_attributes])
  end

  def attach_files
    return if catalog_message?

    super
  end

  def reconcile_existing_message(source_id)
    return super unless catalog_message?
    return false unless find_message_by_source_id(source_id)

    update_message_with_status(@message, status: 'delivered') if outgoing_echo
    @message.assign_attributes(
      content: catalog_normalization[:content],
      content_attributes: @message.content_attributes.to_h.merge(catalog_normalization[:content_attributes])
    )
    @message.save! if @message.changed?
    true
  end

  def catalog_message?
    catalog_message_from(processed_params)
  end

  def catalog_message_from(payload)
    Whatsapp::Unoapi::CatalogMessageNormalizer::CATALOG_TYPES.include?(payload&.dig(:messages, 0, :type).to_s)
  end

  def catalog_normalization
    @catalog_normalization ||= Whatsapp::Unoapi::CatalogMessageNormalizer.new(message: messages_data.first).perform.tap do |result|
      log_catalog_event('unoapi_catalog_normalized', result[:diagnostics])
    end
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
