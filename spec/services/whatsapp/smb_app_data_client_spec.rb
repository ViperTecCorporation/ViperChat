require 'rails_helper'

describe Whatsapp::SmbAppDataClient do
  subject(:client) { described_class.new(channel) }

  let(:provider) { 'whatsapp_cloud' }
  let(:config) { { 'phone_number_id' => '123456789', 'api_key' => 'fake-smb-token' } }
  let(:channel) { instance_double(Channel::Whatsapp, provider: provider, provider_config: config) }
  let(:url) { 'https://graph.facebook.com/v26.0/123456789/smb_app_data' }
  let(:headers) { { 'Content-Type' => 'application/json' } }

  before do
    allow(Whatsapp::ApiVersion).to receive(:current).and_return('v26.0')
  end

  describe '#request' do
    it 'uses its configuration and provider snapshot after the channel is reconfigured' do
      client
      provider.replace('unoapi')
      config['phone_number_id'].replace('987654321')
      config['api_key'].replace('replacement-fake-token')
      allow(channel).to receive_messages(provider: 'unoapi', provider_config: nil)
      request = stub_request(:post, url)
                .with(headers: { 'Authorization' => 'Bearer fake-smb-token' })
                .to_return(status: 200, body: { request_id: 'original-binding' }.to_json, headers: headers)

      expect(client.request('history')).to eq('original-binding')
      expect(request).to have_been_requested.once
    end

    it 'accepts a request ID of exactly 255 bytes' do
      request_id = 'a' * 255
      stub_request(:post, url).to_return(status: 200, body: { request_id: request_id }.to_json, headers: headers)

      expect(client.request('history')).to eq(request_id)
    end

    ['a' * 256, 'é' * 128].each do |request_id|
      it "rejects a request ID of #{request_id.bytesize} bytes without exposing it" do
        request = stub_request(:post, url).to_return(status: 200, body: { request_id: request_id }.to_json, headers: headers)

        expect { client.request('history') }.to raise_error do |error|
          expect(error.class.name).to eq('Whatsapp::SmbAppDataClient::Error')
          expect(error.reason).to eq('invalid_response')
          expect(error.ambiguous?).to be(true)
          expect(error.cause).to be_nil
          expect(error.full_message).not_to include(request_id)
        end
        expect(request).to have_been_requested.once
      end
    end

    %w[smb_app_state_sync history].each do |sync_type|
      it "posts exactly the #{sync_type} payload and returns the request ID" do
        request = stub_request(:post, url)
                  .with(headers: { 'Authorization' => 'Bearer fake-smb-token', 'Content-Type' => 'application/json' },
                        body: { messaging_product: 'whatsapp', sync_type: sync_type }.to_json)
                  .to_return(status: 200, body: { request_id: 'sync-request_123' }.to_json, headers: headers)
        expect(HTTParty).to receive(:post).with(url, hash_including(timeout: 10, follow_redirects: false)).and_call_original

        expect(client.request(sync_type)).to eq('sync-request_123')
        expect(request).to have_been_requested.once
      end
    end

    [nil, '', 'unsupported', :history, {}, 'history?access_token=fake-smb-token'].each do |sync_type|
      it "rejects invalid sync type #{sync_type.inspect} before HTTP" do
        expect(HTTParty).not_to receive(:post)

        expect { client.request(sync_type) }.to raise_error do |error|
          expect(error.class.name).to eq('Whatsapp::SmbAppDataClient::Error')
          expect(error.reason).to eq('invalid_sync_type')
          expect(error.ambiguous?).to be(false)
        end
      end
    end

    [nil, {}, [], { 'api_key' => 'fake-smb-token' },
     { 'phone_number_id' => '../123', 'api_key' => 'fake-smb-token' },
     { 'phone_number_id' => 123, 'api_key' => 'fake-smb-token' },
     { 'phone_number_id' => '123', 'api_key' => '' },
     { 'phone_number_id' => '123', 'api_key' => "fake\r\ntoken" }].each do |invalid_config|
      context "with invalid configuration #{invalid_config.inspect}" do
        let(:config) { invalid_config }

        it 'fails safely before HTTP' do
          expect(HTTParty).not_to receive(:post)

          expect { client.request('history') }.to raise_error do |error|
            expect(error.class.name).to eq('Whatsapp::SmbAppDataClient::Error')
            expect(error.reason).to eq('configuration_missing')
            expect(error.ambiguous?).to be(false)
          end
        end
      end
    end

    context 'with a different provider' do
      let(:provider) { 'unoapi' }

      it 'fails before HTTP' do
        expect(HTTParty).not_to receive(:post)
        expect { client.request('history') }.to raise_error do |error|
          expect(error.reason).to eq('configuration_missing')
          expect(error.ambiguous?).to be(false)
        end
      end
    end

    it 'sanitizes invalid API version errors before HTTP' do
      allow(Whatsapp::ApiVersion).to receive(:current).and_raise(ArgumentError, 'fake-smb-token')
      expect(HTTParty).not_to receive(:post)

      expect { client.request('history') }.to raise_error do |error|
        expect(error.reason).to eq('configuration_missing')
        expect(error.ambiguous?).to be(false)
        expect(error.cause).to be_nil
        expect(error.full_message).not_to include('fake-smb-token')
      end
    end

    [301, 400, 401, 403, 409, 429, 500, 503].each do |status|
      it "treats HTTP #{status} as ambiguous without retrying or exposing the body" do
        request = stub_request(:post, url).to_return(status: status, body: 'private body fake-smb-token',
                                                     headers: headers.merge('Location' => 'https://example.invalid/redirect'))

        expect { client.request('history') }.to raise_error do |error|
          expect(error.class.name).to eq('Whatsapp::SmbAppDataClient::Error')
          expect(error.reason).to eq('http_error')
          expect(error.ambiguous?).to be(true)
          expect(error.full_message).not_to include('private body', 'fake-smb-token')
          expect(error.cause).to be_nil
        end
        expect(request).to have_been_requested.once
      end
    end

    ['not-json fake-smb-token', 'null', '[]', '"fake-smb-token"', '{}',
     '{"request_id":null}', '{"request_id":123}', '{"request_id":""}',
     '{"request_id":" "}', '{"request_id":"id\\nprivate"}',
     '{"request_id":"id","error":{"message":"fake-smb-token"}}'].each do |body|
      it "treats invalid success payload #{body.inspect} as ambiguous" do
        request = stub_request(:post, url).to_return(status: 200, body: body, headers: headers)

        expect { client.request('history') }.to raise_error do |error|
          expect(error.reason).to eq('invalid_response')
          expect(error.ambiguous?).to be(true)
          expect(error.full_message).not_to include('fake-smb-token', 'private')
          expect(error.cause).to be_nil
        end
        expect(request).to have_been_requested.once
      end
    end

    [Timeout::Error, SocketError, Errno::ECONNRESET, OpenSSL::SSL::SSLError].each do |exception|
      it "sanitizes #{exception} and does not retry" do
        request = stub_request(:post, url).to_raise(exception.new('private body fake-smb-token'))

        expect { client.request('history') }.to raise_error do |error|
          expect(error.class.name).to eq('Whatsapp::SmbAppDataClient::Error')
          expect(error.reason).to eq('temporarily_unavailable')
          expect(error.ambiguous?).to be(true)
          expect(error.full_message).not_to include('private body', 'fake-smb-token')
          expect(error.cause).to be_nil
        end
        expect(request).to have_been_requested.once
      end
    end
  end
end
