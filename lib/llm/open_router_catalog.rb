class Llm::OpenRouterCatalog
  class Unavailable < StandardError; end

  BASE_URL = 'https://openrouter.ai/api/v1'.freeze
  CACHE_KEY = 'llm/openrouter/catalog/v1'.freeze

  def models(feature:)
    data = catalog.fetch(feature == 'audio_transcription' ? 'transcription' : 'chat')
    data.select do |model|
      inputs = model.fetch('input_modalities')
      outputs = model.fetch('output_modalities')
      feature == 'audio_transcription' ? inputs.include?('audio') && outputs.include?('transcription') : outputs.include?('text')
    end
  end

  def valid?(feature:, model:)
    models(feature: feature).any? { |item| item['id'] == model }
  end

  private

  def catalog
    Rails.cache.fetch(CACHE_KEY, expires_in: 1.hour) do
      { 'chat' => fetch_models('models'), 'transcription' => fetch_models('models?output_modalities=transcription') }
    end
  end

  def fetch_models(path)
    response = Faraday.get("#{BASE_URL}/#{path}") do |request|
      request.options.timeout = 15
      request.options.open_timeout = 5
    end
    raise Unavailable, 'OpenRouter model catalog unavailable' unless response.success?

    data = JSON.parse(response.body).fetch('data')
    raise Unavailable, 'Invalid OpenRouter model catalog' unless data.is_a?(Array)

    models = data.filter_map { |item| normalize_model(item) }
    models.sort_by { |item| item['name'].downcase }
  rescue Faraday::Error, JSON::ParserError, KeyError
    raise Unavailable, 'OpenRouter model catalog unavailable'
  end

  def normalize_model(item)
    return unless item.is_a?(Hash) && item['id'].is_a?(String) && item['architecture'].is_a?(Hash)

    {
      'id' => item['id'], 'name' => item['name'].presence || item['id'],
      'input_modalities' => Array(item.dig('architecture', 'input_modalities')),
      'output_modalities' => Array(item.dig('architecture', 'output_modalities')),
      'supported_parameters' => Array(item['supported_parameters'])
    }
  end
end
