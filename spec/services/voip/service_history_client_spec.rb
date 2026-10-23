require 'rails_helper'

RSpec.describe Voip::ServiceHistoryClient do
  subject(:client) { described_class.new(service) }

  let(:credentials) do
    { 'integration_provider' => 'viperconnect', 'history_api_url' => 'https://voice.example.com', 'history_api_token' => 'test-secret' }
  end
  let(:service) { instance_double(VoipService, credentials: credentials) }
  let(:url) { 'https://voice.example.com/v1/console/history?sync=changes&limit=100' }
  let(:record) do
    { 'id' => 'record-1', 'callId' => 'sip-1', 'direction' => 'inbound', 'status' => 'completed', 'startedAt' => '2026-10-22T10:00:00Z' }
  end
  let(:payload) do
    { 'version' => 1, 'phase' => 'snapshot', 'items' => [{ 'sequence' => 1, 'record' => record }], 'nextCursor' => 'opaque-2', 'hasMore' => false }
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('voice.example.com').and_return(['93.184.216.34'])
    allow(SafeFetch).to receive(:allow_private_network?).and_return(false)
  end

  it 'reads a snapshot with backend bearer authentication and returns the validated envelope' do
    stub_request(:get, url).with(headers: { 'Authorization' => 'Bearer test-secret', 'Accept' => 'application/json' })
                           .to_return(body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
    expect(client.fetch_changes).to eq(payload)
  end

  it 'passes opaque cursors and bounded limits without interpreting them' do
    payload['phase'] = 'changes'
    request = stub_request(:get, 'https://voice.example.com/v1/console/history').with(query: { sync: 'changes', limit: '1', cursor: 'a+/=' })
                                                                                .to_return(body: payload.to_json,
                                                                                           headers: { 'Content-Type' => 'application/json' })
    expect(client.fetch_changes(cursor: 'a+/=', limit: 1)['phase']).to eq('changes')
    expect(request).to have_been_requested.once
  end

  it 'sends the existing trusted line scope header as JSON, including an explicit deny-all scope' do
    request = stub_request(:get, url).with(headers: { 'X-Unoapi-Session-Scope' => '["5566999999999"]' })
                                     .to_return(body: payload.to_json,
                                                headers: { 'Content-Type' => 'application/json', 'X-Unoapi-Session-Scope-Applied' => '1' })
    client.fetch_changes(session_scope: ['5566999999999'])
    expect(request).to have_been_requested.once
    deny_all = stub_request(:get, url).with(headers: { 'X-Unoapi-Session-Scope' => '[]' })
                                      .to_return(body: payload.merge('items' => []).to_json,
                                                 headers: { 'Content-Type' => 'application/json', 'X-Unoapi-Session-Scope-Applied' => '1' })
    client.fetch_changes(session_scope: [])
    expect(deny_all).to have_been_requested.once
  end

  it 'refuses records when the server does not confirm the requested line isolation' do
    stub_request(:get, url).to_return(body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
    expect { client.fetch_changes(session_scope: ['5566999999999']) }.to raise_error(described_class::ScopeChangedError)
  end

  { 400 => 'InvalidCursorError', 401 => 'AuthenticationError', 403 => 'AuthenticationError', 409 => 'ScopeChangedError',
    410 => 'CursorExpiredError', 501 => 'UnsupportedError', 500 => 'ResponseError', 429 => 'ResponseError' }.each do |status, error_name|
    it "exposes a typed #{status} error without response secrets" do
      stub_request(:get, url).to_return(status: status, body: 'test-secret')
      expect { client.fetch_changes }.to(raise_error do |error|
        expect(error.class.name).to eq("Voip::ServiceHistoryClient::#{error_name}")
        expect(error.message).not_to include('test-secret', 'voice.example.com')
      end)
    end
  end

  it 'rejects redirects without forwarding credentials or requesting the redirect target' do
    stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://other.example.com/stolen' })
    expect { client.fetch_changes }.to raise_error(described_class::Error)
    expect(a_request(:get, 'https://other.example.com/stolen')).not_to have_been_made
  end

  it 'rejects a private destination when private-network access is not explicitly enabled' do
    allow(Resolv).to receive(:getaddresses).with('voice.example.com').and_return(['169.254.169.254'])
    expect { client.fetch_changes }.to raise_error(described_class::ConnectionError)
  end

  it 'allows only the deployment trusted exact HTTPS origin without changing global network policy' do
    allow(Resolv).to receive(:getaddresses).with('voice.example.com').and_return(['192.168.0.50'])
    stub_request(:get, url).to_return(body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
    with_modified_env VOIP_TRUSTED_SERVICE_ORIGINS: 'https://voice.example.com' do
      expect(client.fetch_changes).to eq(payload)
      expect(SafeFetch.allow_private_network?).to be(false)
    end
    ['https://voice.example.com:444', 'https://sub.voice.example.com', 'https://other.example.com'].each do |origin|
      with_modified_env VOIP_TRUSTED_SERVICE_ORIGINS: origin do
        expect { client.fetch_changes }.to raise_error(described_class::ConnectionError)
      end
    end
  end

  it 'rejects malformed and insecure deployment allowlist entries rather than widening access' do
    ['http://voice.example.com', 'https://voice.example.com/path', 'https://user:password@voice.example.com'].each do |origin|
      with_modified_env VOIP_TRUSTED_SERVICE_ORIGINS: origin do
        expect { client.fetch_changes }.to raise_error(described_class::ConfigurationError)
      end
    end
  end

  it 'permits an explicitly enabled private network without following redirects' do
    allow(SafeFetch).to receive(:allow_private_network?).and_return(true)
    allow(Resolv).to receive(:getaddresses).with('voice.example.com').and_return(['192.168.0.50'])
    stub_request(:get, url).to_return(body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
    expect(client.fetch_changes).to eq(payload)
    stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'http://169.254.169.254/latest' })
    expect { client.fetch_changes }.to raise_error(described_class::ResponseError)
    expect(a_request(:get, 'http://169.254.169.254/latest')).not_to have_been_made
  end

  it 'allows HTTP only for a non-production loopback with the private-network policy enabled' do
    credentials['history_api_url'] = 'http://127.0.0.1:3097'
    allow(SafeFetch).to receive(:allow_private_network?).and_return(true)
    stub_request(:get, 'http://127.0.0.1:3097/v1/console/history?sync=changes&limit=100')
      .to_return(body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
    expect(client.fetch_changes).to eq(payload)
    allow(Rails.env).to receive(:production?).and_return(true)
    expect { client.fetch_changes }.to raise_error(described_class::ConfigurationError)
  end

  it 'sanitizes connection errors and removes their potentially sensitive causes' do
    stub_request(:get, url).to_raise(Net::ReadTimeout.new('test-secret and full URL'))
    expect { client.fetch_changes }.to(raise_error do |error|
      expect(error.class.name).to eq('Voip::ServiceHistoryClient::ConnectionError')
      expect(error.message).not_to include('test-secret')
      expect(error.cause).to be_nil
    end)
  end

  ['http://voice.example.com', 'https://user:password@voice.example.com', 'https://voice.example.com?token=x'].each do |base|
    it "rejects unsafe base configuration #{base}" do
      credentials['history_api_url'] = base
      expect { client.fetch_changes }.to raise_error(described_class::ConfigurationError)
    end
  end

  it 'rejects disabled and legacy integrations' do
    credentials['integration_provider'] = 'asterisk'
    expect { client.fetch_changes }.to raise_error(described_class::ConfigurationError)
  end

  it 'rejects excessive cursors and invalid page limits before making requests' do
    expect { client.fetch_changes(cursor: 'a' * 2049) }.to raise_error(described_class::InvalidCursorError)
    expect { client.fetch_changes(limit: 101) }.to raise_error(ArgumentError)
    expect { client.fetch_changes(limit: 0) }.to raise_error(ArgumentError)
  end

  it 'rejects malformed JSON' do
    stub_request(:get, url).to_return(body: '{', headers: { 'Content-Type' => 'application/json' })
    expect { client.fetch_changes }.to raise_error(described_class::ResponseError)
  end

  it 'rejects non-JSON and oversized responses' do
    stub_request(:get, url).to_return(body: '{}', headers: { 'Content-Type' => 'text/html' })
    expect { client.fetch_changes }.to raise_error(described_class::ResponseError)
    stub_request(:get, url).to_return(body: ' ' * (described_class::MAX_BYTES + 1), headers: { 'Content-Type' => 'application/json' })
    expect { client.fetch_changes }.to raise_error(described_class::ResponseError)
  end

  [['version', 2], ['phase', 'unknown'], ['nextCursor', nil], ['hasMore', 'false'], ['items', {}]].each do |key, value|
    it "rejects an invalid envelope #{key}" do
      payload[key] = value
      stub_request(:get, url).to_return(body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
      expect { client.fetch_changes }.to raise_error(described_class::ResponseError)
    end
  end

  it 'rejects invalid event sequences and malformed record timestamps' do
    payload['items'][0]['sequence'] = 0
    stub_request(:get, url).to_return(body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
    expect { client.fetch_changes }.to raise_error(described_class::ResponseError)
    payload['items'][0]['sequence'] = 1
    record['startedAt'] = 'not-a-date'
    stub_request(:get, url).to_return(body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
    expect { client.fetch_changes }.to raise_error(described_class::ResponseError)
  end
end
