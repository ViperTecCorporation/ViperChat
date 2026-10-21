require 'rails_helper'

RSpec.describe 'WhatsApp webhook authentication across phone representations', type: :request do
  let(:account) { create(:account) }
  let(:registered_phone) { '+5581988985300' }
  let(:callback_phone) { '5581988985300' }
  let(:path) { "/webhooks/whatsapp/#{callback_phone}" }
  let(:uno_token) { 'synthetic-uno-webhook-token' }
  let(:meta_secret) { 'synthetic-meta-app-secret' }
  let!(:unoapi) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: registered_phone,
                              provider_config: { 'phone_number_id' => '5581988985300', 'webhook_verify_token' => uno_token },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: registered_phone,
                              provider_config: { 'phone_number_id' => '105303615886039', 'app_secret' => meta_secret, 'source' => 'embedded_signup' },
                              sync_templates: false, validate_provider_config: false).tap do |channel|
      # The common factory assigns its own phone_number_id before create.
      channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => '105303615886039'))
    end
  end
  let(:uno_payload) do
    {
      object: 'whatsapp_business_account', entry: [{ changes: [{ field: 'messages', value: {
        metadata: { display_phone_number: '5581988985300', phone_number_id: '5581988985300' },
        statuses: [{ id: 'synthetic-status', status: 'sent', recipient_id: '5511999999999' }]
      } }] }]
    }
  end
  let(:meta_payload) do
    {
      object: 'whatsapp_business_account', entry: [{ changes: [{ field: 'smb_message_echoes', value: {
        metadata: { display_phone_number: '558188985300', phone_number_id: '105303615886039' },
        message_echoes: [{ id: 'synthetic-meta-echo', from: '558188985300', to: '5511999999999', type: 'text', text: { body: 'Synthetic echo' } }]
      } }] }]
    }
  end
  let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }

  before do
    meta
    InstallationConfig.where(name: 'WHATSAPP_APP_SECRET').delete_all
    GlobalConfig.clear_cache
    allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
  end

  phone_variants = %w[+5581988985300 5581988985300 +558188985300 558188985300]
  authorization_prefixes = [nil, 'Bearer ']
  invalid_tokens = [nil, 'invalid-token', 'Bearer invalid-token']
  invalid_signatures = [nil, 'sha256=invalid']
  phone_variants.each do |stored_phone|
    context "with stored phone #{stored_phone}" do
      let(:registered_phone) { stored_phone }

      phone_variants.each do |url_phone|
        context "with callback phone #{url_phone}" do
          let(:callback_phone) { url_phone }

          authorization_prefixes.each do |prefix|
            it "accepts the valid UnoAPI #{prefix ? 'Bearer' : 'raw'} token without requiring Meta HMAC" do
              post path, params: uno_payload.to_json, headers: headers.merge('Authorization' => "#{prefix}#{uno_token}")

              expect(response).to have_http_status(:ok)
              expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later).once.with(
                hash_including('whatsapp_provider' => 'unoapi', 'whatsapp_channel_id' => unoapi.id)
              )
            end
          end

          invalid_tokens.each do |token|
            it "rejects the #{token.nil? ? 'missing' : token} UnoAPI token without enqueueing" do
              post path, params: uno_payload.to_json, headers: headers.merge('Authorization' => token).compact

              expect(response).to have_http_status(:unauthorized)
              expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
            end
          end

          it 'accepts the official Meta echo only with its valid HMAC, ignoring a wrong UnoAPI token and forged routing hints' do
            body = meta_payload.merge(whatsapp_provider: 'unoapi', whatsapp_channel_id: unoapi.id).to_json
            signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', meta_secret, body)}"
            post path, params: body, headers: headers.merge('X-Hub-Signature-256' => signature, 'Authorization' => 'invalid-token')

            expect(response).to have_http_status(:ok)
            expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later).once do |queued|
              expect(queued['whatsapp_provider']).to eq('whatsapp_cloud')
              expect(queued).not_to have_key('whatsapp_channel_id')
            end
          end

          invalid_signatures.each do |signature|
            it "rejects the #{signature.nil? ? 'missing' : 'invalid'} Meta signature without enqueueing" do
              post path, params: meta_payload.to_json, headers: headers.merge('X-Hub-Signature-256' => signature).compact

              expect(response).to have_http_status(:unauthorized)
              expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
            end
          end
        end
      end
    end
  end

  context 'with only the UnoAPI channel' do
    let(:meta) { nil }

    [nil, 'invalid-token'].each do |token|
      it "requires the #{token.nil? ? 'missing' : 'invalid'} token even for an unambiguous URL with a valid global Meta signature" do
        body = uno_payload.to_json
        signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', meta_secret, body)}"
        with_modified_env WHATSAPP_APP_SECRET: meta_secret do
          post path, params: body, headers: headers.merge('Authorization' => token, 'X-Hub-Signature-256' => signature).compact
        end

        expect(response).to have_http_status(:unauthorized)
        expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
      end
    end
  end

  it 'does not reinterpret an unauthenticated UnoAPI payload as Meta on a shared URL even with a valid global HMAC' do
    body = uno_payload.to_json
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', meta_secret, body)}"
    with_modified_env WHATSAPP_APP_SECRET: meta_secret do
      post path, params: body, headers: headers.merge('Authorization' => 'invalid-token', 'X-Hub-Signature-256' => signature)
    end

    expect(response).to have_http_status(:unauthorized)
    expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
  end

  it 'rejects a correctly formatted HMAC made with the wrong Meta secret' do
    body = meta_payload.to_json
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'different-synthetic-secret', body)}"
    post path, params: body, headers: headers.merge('X-Hub-Signature-256' => signature)

    expect(response).to have_http_status(:unauthorized)
    expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
  end

  it 'rejects an official Meta body modified after signing' do
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', meta_secret, meta_payload.to_json)}"
    meta_payload[:entry][0][:changes][0][:value][:message_echoes][0][:text][:body] = 'Modified synthetic echo'
    post path, params: meta_payload.to_json, headers: headers.merge('X-Hub-Signature-256' => signature)

    expect(response).to have_http_status(:unauthorized)
    expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
  end

  it 'does not accept the token belonging to a different UnoAPI number' do
    other = create(:channel_whatsapp, provider: 'unoapi', phone_number: '+5581981829525',
                                      sync_templates: false, validate_provider_config: false)
    post path, params: uno_payload.to_json, headers: headers.merge('Authorization' => other.provider_config['webhook_verify_token'])

    expect(response).to have_http_status(:unauthorized)
    expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
  end

  %w[sent delivered].product(%w[5511999999999 synthetic@hosted.lid]).each do |status, recipient|
    it "authenticates the log-shaped UnoAPI #{status} independently of recipient #{recipient}" do
      uno_payload[:entry][0][:changes][0][:value][:statuses][0].merge!(status: status, recipient_id: recipient)
      post path, params: uno_payload.to_json, headers: headers.merge('Authorization' => uno_token)

      expect(response).to have_http_status(:ok)
      expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later).once.with(
        hash_including('whatsapp_provider' => 'unoapi', 'whatsapp_channel_id' => unoapi.id)
      )
    end
  end

  it 'authenticates a log-shaped UnoAPI echo without confusing it with the official Meta echo' do
    value = uno_payload[:entry][0][:changes][0]
    value[:field] = 'smb_message_echoes'
    value[:value].delete(:statuses)
    value[:value][:message_echoes] = [{ id: 'synthetic-uno-echo', from: '5581988985300', to: '5511999999999', type: 'text' }]
    post path, params: uno_payload.to_json, headers: headers.merge('Authorization' => uno_token)

    expect(response).to have_http_status(:ok)
    expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later).once.with(
      hash_including('whatsapp_provider' => 'unoapi', 'whatsapp_channel_id' => unoapi.id)
    )
  end

  it 'rejects an ambiguous UnoAPI identity even when both legacy rows share the same token' do
    duplicate = unoapi.dup
    duplicate.phone_number = '+558188985300'
    duplicate.define_singleton_method(:sync_templates) { nil }
    duplicate.save!(validate: false)
    post path, params: uno_payload.to_json, headers: headers.merge('Authorization' => uno_token)

    expect(response).to have_http_status(:unauthorized)
    expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
  end
end
