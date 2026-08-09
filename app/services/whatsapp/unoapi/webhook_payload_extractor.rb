class Whatsapp::Unoapi::WebhookPayloadExtractor
  Result = Data.define(:value, :messages, :source)

  def initialize(params:)
    @params = params.to_h.with_indifferent_access
  end

  def perform
    value = envelope_value.presence || @params
    echoes = Array(value[:message_echoes]).compact
    messages = echoes.presence || Array(value[:messages]).compact

    Result.new(
      value: value,
      messages: messages,
      source: echoes.present? ? :message_echoes : :messages
    )
  end

  private

  def envelope_value
    @params.dig(:entry, 0, :changes, 0, :value)
  end
end
