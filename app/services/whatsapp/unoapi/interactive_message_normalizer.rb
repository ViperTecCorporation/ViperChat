# rubocop:disable Metrics/ClassLength
class Whatsapp::Unoapi::InteractiveMessageNormalizer
  SCHEMA_VERSION = 1
  SUPPORTED_TYPES = %w[button list button_reply list_reply carousel order_details order_status].freeze

  def initialize(message:)
    @message = message.to_h.with_indifferent_access
    @interactive = @message[:interactive].to_h.with_indifferent_access
  end

  def perform
    return if @message[:type].to_s != 'interactive'
    return if interactive_type.blank?

    {
      content: content,
      content_type: carousel? ? 'cards' : 'text',
      content_attributes: content_attributes
    }
  end

  private

  def interactive_type
    @interactive[:type].to_s
  end

  def carousel?
    interactive_type == 'carousel'
  end

  def content
    reply_payload[:title].presence || @interactive.dig(:body, :text).presence || @message[:fallback_text].presence || fallback_content
  end

  def fallback_content
    return I18n.t('conversations.messages.whatsapp.unsupported_message') unless SUPPORTED_TYPES.include?(interactive_type)

    [header[:text], footer[:text]].compact_blank.join("\n").presence
  end

  def content_attributes # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    normalized = {
      schema_version: SCHEMA_VERSION,
      type: interactive_type,
      header: header,
      body: text_block(@interactive[:body]),
      footer: text_block(@interactive[:footer])
    }.compact_blank

    normalized[:reply] = reply_payload if reply_payload.present?
    normalized[:actions] = actions if actions.present?
    normalized[:sections] = sections if sections.present?
    normalized[:button_text] = @interactive.dig(:action, :button).to_s.presence
    normalized[:order] = order_payload if order_payload.present?
    normalized[:status] = status_payload if status_payload.present?
    normalized[:unsupported] = true unless SUPPORTED_TYPES.include?(interactive_type)

    attributes = { whatsapp_interactive: normalized }
    attributes[:items] = carousel_items if carousel?
    attributes
  end

  def header
    payload = @interactive[:header].to_h.with_indifferent_access
    result = text_block(payload)
    image_url = safe_http_url(payload.dig(:image, :link))
    result[:image_url] = image_url if image_url.present?
    result.presence
  end

  def text_block(payload)
    text = payload.to_h.with_indifferent_access[:text].to_s.presence
    text ? { text: text } : {}
  end

  def reply_payload
    payload = @interactive[:button_reply].presence || @interactive[:list_reply].presence
    return {} unless payload.respond_to?(:to_h)

    payload = payload.to_h.with_indifferent_access
    {
      id: payload[:id].to_s.presence,
      title: payload[:title].to_s.presence,
      description: payload[:description].to_s.presence
    }.compact
  end

  def actions
    Array(@interactive.dig(:action, :buttons)).filter_map { |button| normalize_action(button) }
  end

  def normalize_action(button) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    return unless button.respond_to?(:to_h)

    button = button.to_h.with_indifferent_access
    case button[:type].to_s
    when 'reply'
      action('reply', button.dig(:reply, :title), id: button.dig(:reply, :id))
    when 'cta_url'
      action('url', button.dig(:url, :title), url: safe_http_url(button.dig(:url, :link)))
    when 'cta_call'
      action('call', button.dig(:call, :title), phone_number: button.dig(:call, :phone_number).to_s.presence)
    when 'cta_copy'
      action('copy', button.dig(:copy_code, :title), code: button.dig(:copy_code, :code).to_s.presence)
    when 'payment_request'
      payment = normalize_payment_request(button)
      { type: 'payment_request', payment: payment }.compact_blank if payment.present?
    end
  end

  def normalize_payment_request(button)
    return normalize_payment(button[:payment_setting]) if button[:payment_setting].present?

    request = button[:payment_request].to_h.with_indifferent_access
    return {} if request.blank?

    {
      reference_id: request[:reference_id].to_s.presence,
      currency: request[:currency].to_s.presence,
      total_amount: normalize_amount(request[:total_amount]),
      payment_settings: Array(request[:payment_settings]).filter_map { |setting| normalize_payment(setting) }
    }.compact_blank
  end

  def action(type, title, attributes = {})
    { type: type, title: title.to_s.presence }.merge(attributes).compact
  end

  def sections # rubocop:disable Metrics/AbcSize
    Array(@interactive.dig(:action, :sections)).filter_map do |section|
      next unless section.respond_to?(:to_h)

      section = section.to_h.with_indifferent_access
      rows = Array(section[:rows]).filter_map do |row|
        next unless row.respond_to?(:to_h)

        row = row.to_h.with_indifferent_access
        { id: row[:id].to_s.presence, title: row[:title].to_s.presence, description: row[:description].to_s.presence }.compact.presence
      end
      { title: section[:title].to_s.presence, rows: rows }.compact
    end
  end

  def carousel_cards
    @interactive.dig(:action, :carousel, :cards).presence || @interactive.dig(:carousel, :cards)
  end

  def carousel_items # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    Array(carousel_cards).filter_map do |card|
      next unless card.respond_to?(:to_h)

      card = card.to_h.with_indifferent_access
      item = {
        title: card.dig(:header, :text).to_s,
        description: card.dig(:body, :text).to_s,
        media_url: safe_http_url(card.dig(:header, :image, :link)).to_s,
        actions: Array(card.dig(:action, :buttons)).filter_map { |button| normalize_card_action(button) }
      }
      item[:footer] = card.dig(:footer, :text).to_s if card.dig(:footer, :text).present?
      item unless item.values_at(:title, :description, :media_url).all?(&:blank?) && item[:actions].blank? && item[:footer].blank?
    end
  end

  def normalize_card_action(button)
    action = normalize_action(button)
    return if action.blank?

    case action[:type]
    when 'url'
      { type: 'link', text: action[:title], uri: action[:url] }.compact
    when 'reply'
      { type: 'postback', text: action[:title], payload: action[:id] }.compact
    when 'call'
      { type: 'call', text: action[:title], phone_number: action[:phone_number] }.compact
    when 'copy'
      { type: 'copy', text: action[:title], code: action[:code] }.compact
    end
  end

  def order_payload # rubocop:disable Metrics/AbcSize
    return {} unless interactive_type == 'order_details'

    parameters = @interactive.dig(:action, :parameters).to_h.with_indifferent_access
    {
      reference_id: parameters[:reference_id].to_s.presence,
      currency: parameters[:currency].to_s.presence,
      total_amount: normalize_amount(parameters[:total_amount]),
      items: normalize_order_items(parameters.dig(:order, :items)),
      subtotal: normalize_amount(parameters.dig(:order, :subtotal)),
      shipping: normalize_amount(parameters.dig(:order, :shipping), include_description: true),
      discount: normalize_amount(parameters.dig(:order, :discount)),
      tax: normalize_amount(parameters.dig(:order, :tax)),
      payment_settings: Array(parameters[:payment_settings]).filter_map { |setting| normalize_payment(setting) },
      order_status: parameters.dig(:order, :status).to_s.presence
    }.compact_blank
  end

  def status_payload
    return {} unless interactive_type == 'order_status'

    parameters = @interactive.dig(:action, :parameters).to_h.with_indifferent_access
    {
      reference_id: parameters[:reference_id].to_s.presence,
      order: {
        status: parameters.dig(:order, :status).to_s.presence,
        description: parameters.dig(:order, :description).to_s.presence
      }.compact,
      payment: {
        status: parameters.dig(:payment, :status).to_s.presence,
        timestamp: parameters.dig(:payment, :timestamp)
      }.compact
    }.compact_blank
  end

  def normalize_order_items(items)
    Array(items).filter_map do |item|
      next unless item.respond_to?(:to_h)

      item = item.to_h.with_indifferent_access
      {
        retailer_id: item[:retailer_id].to_s.presence,
        name: item[:name].to_s.presence,
        quantity: item[:quantity],
        amount: normalize_amount(item[:amount])
      }.compact_blank
    end
  end

  def normalize_amount(amount, include_description: false)
    amount = amount.to_h.with_indifferent_access
    return {} if amount.blank?

    result = { value: amount[:value], offset: amount[:offset] }
    result[:description] = amount[:description].to_s.presence if include_description
    result.compact
  end

  def normalize_payment(payment) # rubocop:disable Metrics/AbcSize
    payment = payment.to_h.with_indifferent_access
    return {} if payment.blank?

    type = payment[:type].to_s
    details = payment[type].to_h.with_indifferent_access
    result = { type: type }

    case type
    when 'pix_static_code', 'pix_dynamic_code'
      result.merge!(merchant_name: details[:merchant_name].to_s.presence, key: details[:key].to_s.presence,
                    key_type: details[:key_type].to_s.presence, has_dynamic_code: type == 'pix_dynamic_code' && details[:code].present?)
    when 'payment_link'
      result[:url] = safe_http_url(details[:uri])
    when 'boleto'
      result[:digitable_line] = details[:digitable_line].to_s.presence
    when 'offsite_card_pay'
      result[:last_four_digits] = details[:last_four_digits].to_s.presence
    else
      result[:unsupported] = true
    end
    result.compact
  end

  def safe_http_url(value)
    uri = URI.parse(value.to_s)
    uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end
end
# rubocop:enable Metrics/ClassLength
