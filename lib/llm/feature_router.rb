module Llm::FeatureRouter
  class UnknownFeatureError < StandardError; end

  CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'.freeze

  class << self
    def resolve(feature:, account: nil)
      feature_key = feature.to_s
      raise UnknownFeatureError, "Unknown LLM feature: #{feature_key}" unless Llm::Models.feature?(feature_key)

      model, source = resolve_model(feature_key, account)

      {
        feature: feature_key,
        provider: openrouter_route?(feature_key) ? 'openrouter' : Llm::Models.provider_for(model),
        model: model,
        source: source
      }
    end

    private

    def openrouter_route?(feature_key)
      feature_key != 'help_center_search' && Llm::Endpoint.openrouter?
    end

    def resolve_model(feature_key, account)
      override = account_model_override(account, feature_key)
      return [openrouter_route?(feature_key) ? Llm::Endpoint.model_id(override) : override, :account_override] if override
      return [openrouter_model(feature_key), :installation] if openrouter_route?(feature_key)

      transcription = installation_transcription_model(feature_key)
      return [transcription, :installation] if transcription

      [captain_v2_assistant_model(account, feature_key) || Llm::Models.default_model_for(feature_key), :default]
    end

    def installation_transcription_model(feature_key)
      return unless feature_key == 'audio_transcription'

      InstallationConfig.find_by(name: 'CAPTAIN_AUDIO_TRANSCRIPTION_MODEL')&.value.presence
    end

    def openrouter_model(feature_key)
      key = feature_key == 'audio_transcription' ? 'CAPTAIN_AUDIO_TRANSCRIPTION_MODEL' : 'CAPTAIN_OPEN_AI_MODEL'
      value = InstallationConfig.find_by(name: key)&.value.presence ||
              (feature_key == 'audio_transcription' ? 'openai/whisper-1' : 'openai/gpt-4.1-mini')
      Llm::Endpoint.model_id(value)
    end

    def account_model_override(account, feature_key)
      model = account&.captain_models&.[](feature_key).presence
      return unless model
      return model if Llm::Models.valid_model_for?(feature_key, model)
    end

    def captain_v2_assistant_model(account, feature_key)
      return unless feature_key == 'assistant'
      return unless account&.feature_enabled?('captain_integration_v2')

      CAPTAIN_V2_ASSISTANT_MODEL
    end
  end
end
