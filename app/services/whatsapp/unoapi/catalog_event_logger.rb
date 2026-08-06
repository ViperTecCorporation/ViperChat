class Whatsapp::Unoapi::CatalogEventLogger
  class << self
    def log(event, diagnostics)
      Rails.logger.debug { "event=#{event} #{diagnostics.compact.to_json}" }
    end

    def log_broadcast(message_data)
      message_data = message_data.with_indifferent_access
      content_attributes = message_data[:content_attributes].to_h.with_indifferent_access
      catalog_type = content_attributes[:unoapi_message_type]
      return unless Whatsapp::Unoapi::CatalogMessageNormalizer::CATALOG_TYPES.include?(catalog_type)

      catalog = content_attributes[catalog_type == 'order' ? :unoapi_order : :unoapi_catalog].to_h.with_indifferent_access
      log(
        'unoapi_catalog_broadcast',
        source_id: message_data[:source_id],
        phone_number_id: phone_number_id(message_data[:inbox_id]),
        message_type: catalog_type,
        order_id: catalog[:order_id],
        resolution_status: catalog[:resolution_status],
        item_count: catalog[:item_count].presence || Array(catalog[:items]).size,
        chatwoot_message_id: message_data[:id],
        conversation_id: message_data[:conversation_id]
      )
    end

    private

    def phone_number_id(inbox_id)
      Inbox.find_by(id: inbox_id)&.channel&.try(:provider_config)&.[]('phone_number_id')
    end
  end
end
