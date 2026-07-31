class Whatsapp::Unoapi::CatalogMessageNormalizer
  CATALOG_TYPES = %w[product order].freeze
  SENSITIVE_KEYS = %w[token order_token sensitive_string_value media_key direct_path].freeze

  def initialize(message:)
    @message = message.with_indifferent_access
  end

  def perform
    return unless CATALOG_TYPES.include?(message_type)

    catalog_payload = sanitized_value(@message[message_type]).to_h.deep_stringify_keys
    {
      content: @message[:fallback_text].presence || fallback_content(catalog_payload),
      content_attributes: {
        'unoapi_message_type' => message_type,
        catalog_attribute_name => catalog_payload
      },
      diagnostics: diagnostics(catalog_payload)
    }
  end

  private

  def message_type
    @message[:type].to_s
  end

  def catalog_attribute_name
    message_type == 'order' ? 'unoapi_order' : 'unoapi_catalog'
  end

  def fallback_content(catalog_payload)
    lines = [message_type == 'order' ? '*Pedido recebido*' : '*Produto compartilhado*']
    lines << catalog_payload['title'] if catalog_payload['title'].present?
    lines << "Itens: #{catalog_item_count(catalog_payload)}" if message_type == 'order'
    lines.join("\n")
  end

  def diagnostics(catalog_payload)
    {
      source_id: @message[:id],
      message_type: message_type,
      order_id: catalog_payload['order_id'],
      resolution_status: catalog_payload['resolution_status'],
      item_count: catalog_item_count(catalog_payload)
    }.compact
  end

  def catalog_item_count(catalog_payload)
    catalog_payload['item_count'].presence || Array(catalog_payload['items']).size
  end

  def sanitized_value(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), sanitized|
        next if sensitive_key?(key)

        sanitized[key] = sanitized_value(nested_value)
      end
    when Array
      value.map { |nested_value| sanitized_value(nested_value) }
    else
      value
    end
  end

  def sensitive_key?(key)
    SENSITIVE_KEYS.include?(key.to_s.underscore.downcase)
  end
end
