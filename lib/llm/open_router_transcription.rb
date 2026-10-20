class Llm::OpenRouterTranscription
  class Error < StandardError; end

  FORMATS = %w[wav mp3 flac m4a ogg webm aac mp4 opus].freeze

  def self.call(file_path:, model:)
    format = File.extname(file_path).delete_prefix('.').downcase
    format = { 'mpeg' => 'mp3', 'mpga' => 'mp3', 'oga' => 'ogg', 'wave' => 'wav' }.fetch(format, format)
    raise Error, 'Unsupported transcription audio format' unless FORMATS.include?(format)

    key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    raise Error, 'Transcription credentials are missing' if key.blank?

    response = request_transcription(file_path, model, format, key)
    raise Error, "OpenRouter transcription failed (HTTP #{response.status})" unless response.success?

    transcription_text(response.body)
  rescue Faraday::Error, JSON::ParserError
    raise Error, 'OpenRouter transcription unavailable; no automatic retry was attempted'
  end

  def self.request_transcription(file_path, model, format, key)
    Faraday.post('https://openrouter.ai/api/v1/audio/transcriptions') do |request|
      request.headers['Authorization'] = "Bearer #{key}"
      request.headers['Content-Type'] = 'application/json'
      request.options.timeout = 60
      request.options.open_timeout = 10
      request.body = { model: model, input_audio: { data: Base64.strict_encode64(File.binread(file_path)), format: format } }.to_json
    end
  end
  private_class_method :request_transcription

  def self.transcription_text(body)
    text = JSON.parse(body)['text']
    raise Error, 'OpenRouter returned an empty transcription' unless text.is_a?(String) && text.present?

    text
  end
  private_class_method :transcription_text
end
