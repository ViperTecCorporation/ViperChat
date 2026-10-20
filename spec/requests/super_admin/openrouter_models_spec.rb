require 'rails_helper'

RSpec.describe 'Super admin OpenRouter models', type: :request do
  let(:super_admin) { create(:super_admin) }
  before do
    sign_in(super_admin, scope: :super_admin) unless RSpec.current_example.metadata[:ordinary_agent]
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT').update!(value: 'https://openrouter.ai/api/v1')
    allow_any_instance_of(Llm::OpenRouterCatalog).to receive(:models).with(feature: 'assistant')
      .and_return([{ 'id' => 'vendor/chat', 'name' => 'New chat' }])
    allow_any_instance_of(Llm::OpenRouterCatalog).to receive(:models).with(feature: 'audio_transcription')
      .and_return([{ 'id' => 'vendor/stt', 'name' => 'New STT' }])
  end

  it 'renders separate model selectors without losing existing selections' do
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_MODEL').update!(value: 'old/model')
    get '/super_admin/app_config?config=captain'
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    chat = document.at_css('select[name="app_config[CAPTAIN_OPEN_AI_MODEL]"]')
    audio = document.at_css('select[name="app_config[CAPTAIN_AUDIO_TRANSCRIPTION_MODEL]"]')
    expect(chat.css('option').map { |option| option['value'] }).to include('vendor/chat', 'old/model')
    expect(audio.css('option').map { |option| option['value'] }).to include('vendor/stt')
    expect(audio.css('option').map { |option| option['value'] }).not_to include('vendor/chat')
    expect(chat['class']).to include('max-w-full')
  end

  it 'rejects incompatible new models before saving other settings' do
    old_model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
    post '/super_admin/app_config?config=captain', params: { app_config: { CAPTAIN_OPEN_AI_MODEL: 'vendor/invalid', CAPTAIN_AUDIO_TRANSCRIPTION_MODEL: 'vendor/chat' } }
    expect(response).to have_http_status(:redirect)
    expect(InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value).to eq(old_model)
  end

  it 'does not allow ordinary agents to access system model settings', :ordinary_agent do
    sign_in(create(:user), scope: :user)
    get '/super_admin/app_config?config=captain'
    expect(response).to have_http_status(:redirect)
  end
end
