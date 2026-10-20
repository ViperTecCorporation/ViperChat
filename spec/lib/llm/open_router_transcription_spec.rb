require 'rails_helper'

RSpec.describe Llm::OpenRouterTranscription do
  let(:file_path) { Rails.root.join('spec/assets/sample.wav').to_s }

  before do
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: 'synthetic-test-key')
    allow(File).to receive(:binread).with(file_path).and_return('synthetic-audio')
  end

  it 'uses the transcription endpoint and preserves the selected model' do
    request = stub_request(:post, 'https://openrouter.ai/api/v1/audio/transcriptions')
              .with(headers: { Authorization: 'Bearer synthetic-test-key' },
                    body: { model: 'vendor/new-stt', input_audio: { data: Base64.strict_encode64('synthetic-audio'), format: 'wav' } }.to_json)
              .to_return(body: { text: 'Teste de transcrição.' }.to_json)
    expect(described_class.call(file_path: file_path, model: 'vendor/new-stt')).to eq('Teste de transcrição.')
    expect(request).to have_been_requested.once
  end

  it 'does not leak provider bodies or retry failed paid calls' do
    request = stub_request(:post, 'https://openrouter.ai/api/v1/audio/transcriptions').to_return(status: 401,
                                                                                                 body: 'synthetic-test-key private details')
    expect { described_class.call(file_path: file_path, model: 'vendor/new-stt') }
      .to raise_error(described_class::Error, 'OpenRouter transcription failed (HTTP 401)')
    expect(request).to have_been_requested.once
  end

  it 'rejects empty success responses' do
    stub_request(:post, 'https://openrouter.ai/api/v1/audio/transcriptions').to_return(body: { text: '' }.to_json)
    expect { described_class.call(file_path: file_path, model: 'vendor/new-stt') }.to raise_error(described_class::Error)
  end

  it 'rejects unsupported formats before any paid request' do
    expect { described_class.call(file_path: 'sample.exe', model: 'vendor/new-stt') }.to raise_error(described_class::Error)
    expect(a_request(:post, 'https://openrouter.ai/api/v1/audio/transcriptions')).not_to have_been_made
  end

  it 'accepts MPEG filename aliases as MP3 input' do
    allow(File).to receive(:binread).with('audio.mpeg').and_return('synthetic-audio')
    request = stub_request(:post, 'https://openrouter.ai/api/v1/audio/transcriptions')
              .with { |req| JSON.parse(req.body).dig('input_audio', 'format') == 'mp3' }
              .to_return(body: { text: 'Transcript' }.to_json)
    expect(described_class.call(file_path: 'audio.mpeg', model: 'vendor/new-stt')).to eq('Transcript')
    expect(request).to have_been_requested.once
  end
end
