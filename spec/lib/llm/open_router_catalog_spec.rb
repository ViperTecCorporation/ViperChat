require 'rails_helper'

RSpec.describe Llm::OpenRouterCatalog do
  let(:chat) do
    { id: 'vendor/new-chat', name: 'New chat', architecture: { input_modalities: ['text'], output_modalities: ['text'] },
      supported_parameters: ['tools'] }
  end
  let(:audio) { { id: 'vendor/new-stt', name: 'New STT', architecture: { input_modalities: ['audio'], output_modalities: ['transcription'] } } }

  before do
    Rails.cache.delete(described_class::CACHE_KEY)
    stub_request(:get, 'https://openrouter.ai/api/v1/models').to_return(body: { data: [chat, audio] }.to_json)
    stub_request(:get, 'https://openrouter.ai/api/v1/models?output_modalities=transcription').to_return(body: { data: [audio, chat] }.to_json)
  end

  after { Rails.cache.delete(described_class::CACHE_KEY) }

  it 'discovers new model slugs without a hard-coded registry' do
    expect(described_class.new.models(feature: 'assistant').pluck('id')).to eq(['vendor/new-chat'])
    expect(described_class.new.models(feature: 'audio_transcription').pluck('id')).to eq(['vendor/new-stt'])
  end

  it 'rejects a chat model as a transcription model' do
    expect(described_class.new.valid?(feature: 'audio_transcription', model: 'vendor/new-chat')).to be(false)
  end

  it 'does not attach credentials to catalog requests' do
    described_class.new.models(feature: 'assistant')
    expect(a_request(:get, 'https://openrouter.ai/api/v1/models').with { |request| request.headers['Authorization'].present? }).not_to have_been_made
  end

  it 'surfaces catalog errors without replacing them with an empty success' do
    stub_request(:get, 'https://openrouter.ai/api/v1/models').to_return(status: 503)
    expect { described_class.new.models(feature: 'assistant') }.to raise_error(described_class::Unavailable)
  end

  it 'normalizes API versions only once' do
    expect(Llm::Endpoint.api_base('https://openrouter.ai/api/v1/')).to eq('https://openrouter.ai/api/v1')
    expect(Llm::Endpoint.api_base('https://api.openai.com')).to eq('https://api.openai.com/v1')
    expect(Llm::Endpoint.openrouter?('https://openrouter.ai.evil.example/api/v1')).to be(false)
    expect(Llm::Endpoint.openrouter?('http://openrouter.ai/api/v1')).to be(false)
  end

  it 'routes the global model even when Captain V2 would choose a fixed default' do
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT').update!(value: 'https://openrouter.ai/api/v1')
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_MODEL').update!(value: 'vendor/new-chat')
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_AUDIO_TRANSCRIPTION_MODEL').update!(value: 'vendor/new-stt')
    account = create(:account)
    account.enable_features!('captain_integration_v2')
    expect(Llm::FeatureRouter.resolve(feature: 'assistant', account: account)).to include(model: 'vendor/new-chat', source: :installation)
    expect(Llm::FeatureRouter.resolve(feature: 'audio_transcription')).to include(model: 'vendor/new-stt')
    expect(Llm::FeatureRouter.resolve(feature: 'help_center_search')).to include(model: 'text-embedding-3-small', source: :default)
    expect(Llm::Endpoint.chat_options).to eq(provider: :openai, assume_model_exists: true)
    account.update!(captain_models: { 'assistant' => 'gpt-5.1' })
    expect(Llm::FeatureRouter.resolve(feature: 'assistant', account: account))
      .to include(model: 'openai/gpt-5.1', source: :account_override, provider: 'openrouter')
  end
end
