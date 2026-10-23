require 'rails_helper'

RSpec.describe Voip::RecordingClient do
  let(:service) do
    instance_double(VoipService, credentials: { 'integration_provider' => 'viperconnect', 'history_api_url' => 'https://voice.example.com',
                                                'history_api_token' => 'test-secret' })
  end
  let(:url) { 'https://voice.example.com/v1/console/history-records/record-1/recording' }
  let(:recording) { { 'record_id' => 'record-1', 'status' => 'available' } }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('voice.example.com').and_return(['93.184.216.34'])
    allow(SafeFetch).to receive(:allow_private_network?).and_return(false)
  end

  it 'downloads only the configured record route using backend authentication and verifies bytes' do
    request = stub_request(:get, url).with(headers: { 'Authorization' => 'Bearer test-secret' })
                                     .to_return(body: 'test-audio', headers: { 'Content-Type' => 'audio/wav' })
    recording.merge!('size_bytes' => 10, 'sha256' => Digest::SHA256.hexdigest('test-audio'))
    result = described_class.new(service).fetch(recording)
    expect(result[:file].read).to eq('test-audio')
    expect(result[:digest]).to eq(recording['sha256'])
    expect(request).to have_been_requested.once
  ensure
    result&.dig(:file)&.close!
  end

  it 'refuses redirects without forwarding its token to another host' do
    stub_request(:get, url).to_return(status: 302, headers: { Location: 'https://other.example.com/recording' })
    expect { described_class.new(service).fetch(recording) }.to raise_error(Voip::ServiceHistoryClient::ResponseError)
    expect(a_request(:get, 'https://other.example.com/recording')).not_to have_been_made
  end

  it 'refuses private network destinations unless explicitly permitted by the deployment' do
    allow(Resolv).to receive(:getaddresses).with('voice.example.com').and_return(['169.254.169.254'])
    expect { described_class.new(service).fetch(recording) }.to raise_error(Voip::ServiceHistoryClient::ResponseError)
  end

  it 'refuses nonaudio, oversized responses and changed hashes without exposing credentials' do
    [{ 'Content-Type' => 'text/html' }, { 'Content-Type' => 'audio/wav', 'Content-Length' => (51.megabytes).to_s }].each do |headers|
      stub_request(:get, url).to_return(body: 'test-secret', headers: headers)
      expect { described_class.new(service).fetch(recording) }.to raise_error(Voip::ServiceHistoryClient::ResponseError, 'Recording fetch failed')
    end
    stub_request(:get, url).to_return(body: 'test-secret', headers: { 'Content-Type' => 'audio/wav' })
    recording['sha256'] = 'a' * 64
    expect { described_class.new(service).fetch(recording) }.to raise_error(Voip::ServiceHistoryClient::ResponseError, 'Recording fetch failed')
  end
end
