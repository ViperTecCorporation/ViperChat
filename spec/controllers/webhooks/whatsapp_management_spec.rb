require 'rails_helper'

RSpec.describe 'Meta management webhook signature', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:secret) { 'synthetic-management-secret' }
  let(:payload) do
    { object: 'whatsapp_business_account', entry: [{ id: channel.provider_config['business_account_id'], changes: [
      { field: 'business_capability_update', value: { max_daily_conversations_per_business: 'TIER_2K' } }
    ] }] }.to_json
  end

  before do
    channel.update!(provider_config: channel.provider_config.merge('source' => 'manual', 'app_secret' => secret))
  end

  it 'accepts signed WABA events without phone metadata' do
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}"
    expect do
      post "/webhooks/whatsapp/#{channel.phone_number}", params: payload,
                                                         headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature }
    end.to have_enqueued_job(Webhooks::WhatsappEventsJob)
    expect(response).to have_http_status(:ok)
  end

  it 'rejects unsigned admin events even on manual Cloud channels without a local secret' do
    channel.update!(provider_config: channel.provider_config.except('app_secret'))
    expect do
      post "/webhooks/whatsapp/#{channel.phone_number}", params: payload, headers: { 'CONTENT_TYPE' => 'application/json' }
    end.not_to have_enqueued_job(Webhooks::WhatsappEventsJob)
    expect(response).to have_http_status(:unauthorized)
  end
end
