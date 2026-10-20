module Llm::Endpoint
  def self.api_base(endpoint = nil)
    base = (endpoint.presence || 'https://api.openai.com').chomp('/')
    base.end_with?('/v1') ? base : "#{base}/v1"
  end

  def self.openrouter?(endpoint = nil)
    endpoint ||= InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    uri = URI.parse(endpoint.to_s)
    uri.scheme == 'https' && uri.host == 'openrouter.ai' && uri.port == 443
  rescue URI::InvalidURIError
    false
  end

  def self.chat_options
    openrouter? ? { provider: :openai, assume_model_exists: true } : {}
  end

  def self.model_id(model)
    return model unless openrouter? && model.present? && model.exclude?('/')
    return model unless LlmConstants::PROVIDER_PREFIXES.fetch('openai').any? { |prefix| model.start_with?(prefix) }

    "openai/#{model}"
  end
end
