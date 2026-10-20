require 'rails_helper'
require 'base64'
require 'stringio'

RSpec.describe 'Meta historical webhook automatic ingestion', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:secret) { 'synthetic-history-secret' }
  let!(:contact) { create(:contact, account: channel.account, phone_number: '+5566996269251', name: 'Nome antigo preservado') }
  let(:message) { { id: 'history-signed-1', from: '5566996269251', timestamp: 1.day.ago.to_i.to_s, type: 'text', text: { body: 'Histórico' } } }
  let(:messages) { [message] }
  let(:payload) do
    { object: 'whatsapp_business_account', entry: [{ id: channel.provider_config['business_account_id'], changes: [
      { field: 'history', value: { history: [{ threads: [{ id: '5566996269251', messages: messages }] }] } }
    ] }] }.to_json
  end
  let(:headers) do
    { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}" }
  end

  before do
    channel.update!(provider_config: channel.provider_config.merge('ignore_history_messages' => false, 'app_secret' => secret))
  end

  it 'imports a signed history webhook automatically and deduplicates its redelivery without sending anything' do
    2.times do
      perform_enqueued_jobs(only: [Webhooks::WhatsappEventsJob, Whatsapp::ImportHistoryJob]) do
        post "/webhooks/whatsapp/#{channel.phone_number}", params: payload, headers: headers
      end
      expect(response).to have_http_status(:ok)
    end

    expect(channel.account.messages.where(message_type: :incoming).pluck(:source_id)).to eq([message[:id]])
    expect(channel.account.contacts.pluck(:id)).to eq([contact.id])
    expect(contact.reload.name).to eq('Nome antigo preservado')
    expect(WhatsappManagementEvent.sole.state).to eq('processed')
    expect(SendReplyJob).not_to have_been_enqueued
  end

  it 'does not import an unsigned history request' do
    expect do
      post "/webhooks/whatsapp/#{channel.phone_number}", params: payload, headers: { 'CONTENT_TYPE' => 'application/json' }
    end.not_to have_enqueued_job(Webhooks::WhatsappEventsJob)
    expect(response).to have_http_status(:unauthorized)
    expect(channel.account.messages).to be_empty
  end

  context 'with initial SMB synchronization requested' do
    let(:admin) { create(:user, account: channel.account, role: :administrator) }
    let(:media_message) do
      message.merge(id: 'history-signed-image', type: 'image', text: nil,
                    image: { id: '111333', mime_type: 'image/png', caption: 'Imagem histórica' }).compact
    end
    let(:messages) { [message, message.merge(id: 'out-of-period', timestamp: 4.days.ago.to_i.to_s), media_message] }

    around do |example|
      with_modified_env WHATSAPP_SMB_SYNC_ENABLED: 'true' do
        example.run
      end
    end

    before do
      channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => '111222', 'business_account_id' => '333444'))
      allow(Whatsapp::ApiVersion).to receive(:current).and_return('v26.0')
      stub_request(:get, 'https://graph.facebook.com/v26.0/111222')
        .with(query: { fields: 'is_on_biz_app,platform_type' })
        .to_return(status: 200, body: { is_on_biz_app: true, platform_type: 'CLOUD_API' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://graph.facebook.com/v26.0/333444/subscribed_apps')
        .with { |request| (%w[history smb_app_state_sync smb_message_echoes] - JSON.parse(request.body)['subscribed_fields']).empty? }
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://graph.facebook.com/v26.0/111222')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      %w[smb_app_state_sync history].each do |type|
        stub_request(:post, 'https://graph.facebook.com/v26.0/111222/smb_app_data')
          .with(body: { messaging_product: 'whatsapp', sync_type: type }.to_json)
          .to_return(status: 200, body: { request_id: "request-#{type}" }.to_json, headers: { 'Content-Type' => 'application/json' })
      end
      stub_request(:get, channel.media_url('111333'))
        .to_return(status: 200, body: { url: 'https://history-media.invalid/initial.png' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      allow(Down).to receive(:download).with('https://history-media.invalid/initial.png', headers: anything) do
        bytes = Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
        StringIO.new(bytes).tap do |io|
          io.define_singleton_method(:original_filename) { 'initial.png' }
          io.define_singleton_method(:content_type) { 'image/png' }
        end
      end
    end

    it 'imports redelivered two-day history once without duplicating media', :aggregate_failures do
      initial_blobs = ActiveStorage::Blob.count
      2.times do
        perform_enqueued_jobs(only: Whatsapp::RequestSmbAppDataJob) do
          patch "/api/v1/accounts/#{channel.account_id}/inboxes/#{channel.inbox.id}/coexistence_settings",
                headers: admin.create_new_auth_token, params: { ignore_history_messages: false, history_max_age_days: 2 }, as: :json
        end
        expect(response).to have_http_status(:ok)
        perform_enqueued_jobs(only: [Webhooks::WhatsappEventsJob, Whatsapp::ImportHistoryJob]) do
          post "/webhooks/whatsapp/#{channel.phone_number}", params: payload, headers: headers
        end
        expect(response).to have_http_status(:ok)
      end
      expect(channel.account.messages.where(message_type: :incoming).pluck(:source_id)).to contain_exactly(message[:id], media_message[:id])
      expect(channel.account.contacts.pluck(:id)).to eq([contact.id])
      expect(contact.reload.name).to eq('Nome antigo preservado')
      expect(Attachment.count).to eq(1)
      expect(ActiveStorage::Blob.count - initial_blobs).to eq(1)
      expect(Down).to have_received(:download).once
      expect(WhatsappSmbSyncRequest.where(state: 'accepted').count).to eq(2)
      expect(WebMock).to have_requested(:post, 'https://graph.facebook.com/v26.0/111222/smb_app_data').twice
      expect(SendReplyJob).not_to have_been_enqueued
      expect(AgentBots::WebhookJob).not_to have_been_enqueued
    end
  end

  context 'with a large but individually valid batch' do
    let(:messages) { Array.new(3) { |index| message.merge(id: "large-history-#{index}", text: { body: 'a' * 100_000 }) } }

    it 'splits before retention truncation and imports all items once' do
      perform_enqueued_jobs(only: [Webhooks::WhatsappEventsJob, Whatsapp::ImportHistoryJob]) do
        post "/webhooks/whatsapp/#{channel.phone_number}", params: payload, headers: headers
      end
      expect(response).to have_http_status(:ok)
      expect(channel.account.messages.where(message_type: :incoming).count).to eq(3)
      expect(WhatsappManagementEvent.pluck(:state)).to eq(%w[processed processed processed])
      expect(channel.account.contacts.count).to eq(1)
    end
  end
end
