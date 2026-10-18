# Deliberately supports the formats offered by the creation form, not arbitrary Graph JSON.
class Whatsapp::TemplateDefinition
  include ActiveModel::Validations

  CATEGORIES = %w[MARKETING UTILITY].freeze
  BUTTON_TYPES = %w[URL QUICK_REPLY].freeze
  attr_reader :data

  validate :valid_definition

  def initialize(data)
    @data = data.deep_stringify_keys
  end

  def payload
    validate!
    { name: data['name'], language: data['language'], category: data['category'], parameter_format: 'POSITIONAL',
      components: components }.deep_stringify_keys
  end

  def read_attribute_for_validation(attribute)
    data[attribute.to_s]
  end

  private

  def valid_definition
    validate_identity
    errors.add(:body, :blank) if data['body'].blank?
    validate_text('body', 1024)
    validate_text('header', 60)
    validate_text('footer', 60)
    validate_variables if data['body'].is_a?(String)
    validate_buttons
  end

  def validate_identity
    errors.add(:name, :invalid) unless data['name'].is_a?(String) && /\A[a-z0-9_]{1,512}\z/.match?(data['name'])
    errors.add(:language, :invalid) unless data['language'].is_a?(String) && /\A[a-z]{2,3}(?:_[A-Z]{2})?\z/.match?(data['language'])
    errors.add(:category, :invalid) unless CATEGORIES.include?(data['category'])
  end

  def validate_text(key, limit)
    value = data[key]
    return if value.nil?

    errors.add(key, :invalid) unless valid_text?(value, limit)
    errors.add(key, :invalid_variables) if key != 'body' && value.to_s.match?(/[{}]/)
  end

  def valid_text?(value, limit)
    value.is_a?(String) && value.length <= limit
  end

  def validate_variables
    body = data['body']
    variables = body.scan(/\{\{([1-9]\d*)\}\}/).flatten.uniq
    # Reject named, unclosed, zero-prefixed and out-of-sequence placeholders.
    invalid = body.gsub(/\{\{[1-9]\d*\}\}/, '').match?(/[{}]/) || variables != (1..variables.size).map(&:to_s)
    errors.add(:body, :invalid_variables) if invalid
    examples = data.fetch('examples', [])
    return if valid_examples?(examples, variables.size)

    errors.add(:examples, :invalid)
  end

  def valid_examples?(examples, count)
    examples.is_a?(Array) && examples.size == count && examples.all? { |value| valid_text?(value, 1024) && value.present? }
  end

  def validate_buttons
    buttons = data.fetch('buttons', [])
    unless buttons.is_a?(Array) && buttons.size <= 3 && buttons.all?(Hash)
      errors.add(:buttons, :invalid)
      return
    end
    errors.add(:buttons, :invalid) unless valid_button_types?(buttons)
    buttons.each { |button| validate_button(button) }
  end

  def valid_button_types?(buttons)
    types = buttons.pluck('type').uniq
    types.size <= 1 && (types != ['URL'] || buttons.size <= 2)
  end

  def validate_button(button)
    text = button['text']
    valid = BUTTON_TYPES.include?(button['type']) && valid_text?(text, 25) && text.present? && !text.match?(/[{}]/)
    errors.add(:buttons, :invalid) unless valid
    return unless button['type'] == 'URL'

    errors.add(:buttons, :invalid_url) unless valid_url?(button['url'])
  end

  def valid_url?(url)
    return false unless url.is_a?(String) && url.length <= 2000 && !url.match?(/[{}\s]|%7[bd]/i)

    uri = URI.parse(url)
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  def components
    result = []
    result << { type: 'HEADER', format: 'TEXT', text: data['header'] } if data['header'].present?
    result << body_component
    result << { type: 'FOOTER', text: data['footer'] } if data['footer'].present?
    result << { type: 'BUTTONS', buttons: button_components } if data['buttons'].present?
    result
  end

  def body_component
    body = { type: 'BODY', text: data['body'] }
    body[:example] = { body_text: [data['examples']] } if data['examples'].present?
    body
  end

  def button_components
    data['buttons'].map do |button|
      button['type'] == 'URL' ? button.slice('type', 'text', 'url') : button.slice('type', 'text')
    end
  end
end
