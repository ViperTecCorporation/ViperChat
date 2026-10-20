require 'rails_helper'

RSpec.describe 'WhatsApp coexistence webhook routing', type: :request do
  let(:account) { create(:account) }
  let(:payload) do
    {
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ field: 'messages', value: { metadata: {
        display_phone_number: '558188985300', phone_number_id: meta.provider_config['phone_number_id']
      } } }] }]
    }
  end
  let!(:unoapi) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5581988985300',
                              provider_config: { 'phone_number_id' => 'uno-business' },
                              sync_templates: false, validate_provider_config: false)
  end
  let!(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: unoapi.phone_number,
                              sync_templates: false, validate_provider_config: false)
  end
  let(:path) { "/webhooks/whatsapp/#{meta.phone_number}" }

  before do
    InstallationConfig.where(name: 'WHATSAPP_APP_SECRET').delete_all
    GlobalConfig.clear_cache
  end

  it 'verifies the Meta token even when ViperConnect was registered first' do
    get path, params: { 'hub.verify_token' => meta.provider_config['webhook_verify_token'], 'hub.challenge' => 'coexistence' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('coexistence')
  end

  it 'routes signed Meta events with an eight-digit display number to Meta and discards client routing hints' do
    payload[:whatsapp_provider] = 'unoapi'
    payload[:whatsapp_channel_id] = unoapi.id
    body = payload.to_json
    secret = 'coexistence-app-secret'
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    expect(Webhooks::WhatsappEventsJob).to receive(:perform_later) do |queued|
      expect(queued).to include('whatsapp_provider' => 'whatsapp_cloud')
      expect(queued).not_to have_key('whatsapp_channel_id')
    end
    with_modified_env WHATSAPP_APP_SECRET: secret do
      post path, params: body, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature }
    end
    expect(response).to have_http_status(:ok)
  end

  it 'routes authenticated ViperConnect events to their original inbox' do
    payload[:entry].first[:changes].first[:value][:metadata][:phone_number_id] = 'uno-business'
    expect(Webhooks::WhatsappEventsJob).to receive(:perform_later).with(
      hash_including('whatsapp_provider' => 'unoapi', 'whatsapp_channel_id' => unoapi.id)
    )
    post path, params: payload.to_json, headers: {
      'CONTENT_TYPE' => 'application/json', 'Authorization' => unoapi.provider_config['webhook_verify_token']
    }
    expect(response).to have_http_status(:ok)
  end

  it 'retains signed administrative Meta events without message metadata on the shared callback' do
    payload[:entry].first[:changes] = [{ field: 'account_alerts', value: { alert_type: 'TEST_ALERT' } }]
    body = payload.to_json
    secret = 'coexistence-administrative-secret'
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    expect(Webhooks::WhatsappEventsJob).to receive(:perform_later).with(hash_including('whatsapp_provider' => 'whatsapp_cloud'))
    with_modified_env WHATSAPP_APP_SECRET: secret do
      post path, params: body, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature }
    end
    expect(response).to have_http_status(:ok)
  end

  it 'does not bypass Meta signature validation with a forged ViperConnect routing hint' do
    payload[:whatsapp_provider] = 'unoapi'
    payload[:whatsapp_channel_id] = unoapi.id
    expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)
    post path, params: payload.to_json, headers: { 'CONTENT_TYPE' => 'application/json', 'Authorization' => 'wrong-token' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an ambiguous unsigned event instead of selecting the first channel' do
    payload[:entry].first[:changes].first[:value][:metadata][:phone_number_id] = 'unknown-business'
    expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)
    post path, params: payload.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end
end
