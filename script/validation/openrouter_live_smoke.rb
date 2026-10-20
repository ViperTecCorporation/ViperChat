# Standalone diagnostic CLI: retain machine-readable stdout, exit status and atomic fixture scenarios.
# rubocop:disable Metrics/BlockLength, Rails/Output, Rails/Exit
# Minimal paid validation. Pass {"api_key":"..."} over stdin, never arguments or a file.
# Runs only in the existing isolated test database and rolls all config writes back.
require 'open3'
require 'tempfile'
require 'agents'

raise 'Explicit smoke confirmation required' unless ENV['CONFIRM_OPENROUTER_SMOKE'] == '1'
raise 'Isolated test database required' unless Rails.env.test? && ActiveRecord::Base.connection.current_database == 'viperchat_meta_embed_validation'

credentials = JSON.parse($stdin.read)
raise 'Missing API key' if credentials['api_key'].blank?

report = {}
begin
  ActiveRecord::Base.transaction do
    {
      'CAPTAIN_OPEN_AI_API_KEY' => credentials.fetch('api_key'),
      'CAPTAIN_OPEN_AI_ENDPOINT' => 'https://openrouter.ai/api/v1',
      'CAPTAIN_OPEN_AI_MODEL' => 'openai/gpt-4o-mini',
      'CAPTAIN_AUDIO_TRANSCRIPTION_MODEL' => 'openai/whisper-1'
    }.each { |name, value| InstallationConfig.find_or_initialize_by(name: name).update!(value: value) }

    report[:stage] = 'catalog'
    catalog = Llm::OpenRouterCatalog.new
    report[:chat_models] = catalog.models(feature: 'assistant').size
    report[:transcription_models] = catalog.models(feature: 'audio_transcription').size
    Llm::Config.reset!
    Llm::Config.initialize!

    report[:stage] = 'chat'
    unless credentials['skip_chat']
      Llm::Config.with_api_key(credentials.fetch('api_key'), api_base: Llm::Endpoint.api_base('https://openrouter.ai/api/v1')) do |context|
        response = context.chat(model: 'openai/gpt-4o-mini', **Llm::Endpoint.chat_options)
                          .with_params(max_tokens: 24).ask('Reply only: validation ok')
        raise 'Empty chat response' if response.content.blank?

        report[:chat] = 'passed'
      end
    end

    report[:stage] = 'agent_schema'
    schema = { type: 'object', properties: { result: { type: 'string' } }, required: ['result'], additionalProperties: false }
    agent = Agents::Agent.new(name: 'Synthetic validation', model: 'openai/gpt-4o-mini',
                              instructions: 'Answer with result set to ok. No real user data is provided.',
                              response_schema: schema, **Llm::Endpoint.chat_options)
    result = Agents::Runner.with_agents(agent).run('Validate the structured response.', max_turns: 1, params: { max_tokens: 48 })
    output = result.output.is_a?(String) ? JSON.parse(result.output) : result.output
    raise 'Invalid structured response' unless output['result'] == 'ok' || output[:result] == 'ok'

    report[:captain_agent_schema] = 'passed'

    report[:stage] = 'transcription'
    audio, _stderr, status = Open3.capture3('ffmpeg', '-v', 'error', '-i', Rails.root.join('spec/assets/sample.mp3').to_s,
                                            '-t', '3', '-ac', '1', '-ar', '16000', '-f', 'wav', 'pipe:1')
    raise 'Synthetic audio preparation failed' unless status.success? && audio.bytesize.positive?

    Tempfile.create(['viperchat-openrouter-smoke-', '.wav']) do |file|
      file.binmode
      file.write(audio)
      file.flush
      text = Llm::OpenRouterTranscription.call(file_path: file.path, model: 'openai/whisper-1')
      raise 'Empty transcription' if text.blank?

      report[:transcription] = 'passed'
      report[:audio_seconds] = 3
    end
    raise ActiveRecord::Rollback
  end
  puts report.merge(production_changed: false, configs_persisted: false).to_json
rescue StandardError => e
  puts report.merge(error_class: e.class.name, location: e.backtrace&.first&.split(':in')&.first).to_json
  exit 1
end

# rubocop:enable Metrics/BlockLength, Rails/Output, Rails/Exit
