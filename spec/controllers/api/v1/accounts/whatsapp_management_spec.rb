require 'rails_helper'

RSpec.describe 'Meta management account API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}" }

  it 'shows safe receipt summaries and the default history policy' do
    get "#{url}/management_events", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['history_settings']).to eq('ignore_history_messages' => true, 'history_max_age_days' => 7, 'ignore_group_messages' => false)
    expect(response.parsed_body['supported_fields']).to include('smb_app_state_sync', 'history', 'security', 'business_capability_update')
    expect(response.parsed_body).not_to have_key('payload')
  end

  it 'updates only history settings and preserves credentials and current provider IDs' do
    previous = channel.provider_config.deep_dup
    expect do
      patch "#{url}/coexistence_settings", headers: admin.create_new_auth_token,
            params: { ignore_history_messages: false, history_max_age_days: 15, api_key: 'must-not-change' }, as: :json
    end.to have_enqueued_job(Whatsapp::RequestSmbAppDataJob).with(channel.id)
    expect(response).to have_http_status(:ok)
    expect(channel.reload.provider_config).to eq(previous.merge('ignore_history_messages' => false, 'history_max_age_days' => 15))
  end

  it 'does not enqueue a one-time Meta request when history is ignored' do
    expect do
      patch "#{url}/coexistence_settings", headers: admin.create_new_auth_token,
            params: { ignore_history_messages: true, history_max_age_days: 7 }, as: :json
    end.not_to have_enqueued_job(Whatsapp::RequestSmbAppDataJob)
  end

  it 'returns only the current account and channel request summaries without credentials' do
    WhatsappSmbSyncRequest.create!(account: account, channel: channel, phone_number_id: '123', waba_id: '456', sync_type: 'history',
                                 state: 'accepted', request_id: 'history-request', history_max_age_days: 15)
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    WhatsappSmbSyncRequest.create!(account: other.account, channel: other, phone_number_id: '789', waba_id: '456', sync_type: 'history',
                                 state: 'uncertain', history_max_age_days: 7)
    get "#{url}/management_events", headers: admin.create_new_auth_token
    expect(response.parsed_body.dig('initial_history_sync', 'requests').size).to eq(1)
    expect(response.parsed_body.dig('initial_history_sync', 'requests', 0)).to include('request_id' => 'history-request', 'state' => 'accepted')
    expect(response.parsed_body.to_s).not_to include('api_key', 'phone_number_id', 'waba_id')
  end

  it 'rejects invalid days and ambiguous booleans' do
    patch "#{url}/coexistence_settings", headers: admin.create_new_auth_token,
          params: { ignore_history_messages: 'false', history_max_age_days: 0 }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(channel.reload.provider_config).not_to have_key('history_max_age_days')
  end

  it 'persists an explicit group preference and preserves it when an older client omits the field' do
    headers = admin.create_new_auth_token
    patch "#{url}/coexistence_settings", headers: headers,
          params: { ignore_history_messages: false, history_max_age_days: 7, ignore_group_messages: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(channel.reload.provider_config['ignore_group_messages']).to be(true)
    patch "#{url}/coexistence_settings", headers: headers,
          params: { ignore_history_messages: true, history_max_age_days: 14 }, as: :json
    expect(response).to have_http_status(:ok)
    expect(channel.reload.provider_config['ignore_group_messages']).to be(true)
  end

  it 'rejects ambiguous group settings without overwriting any provider configuration' do
    previous = channel.provider_config.deep_dup
    patch "#{url}/coexistence_settings", headers: admin.create_new_auth_token,
          params: { ignore_history_messages: false, history_max_age_days: 7, ignore_group_messages: 'false' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(channel.reload.provider_config).to eq(previous)
  end

  it 'denies an ordinary inbox agent and an inbox from a different account' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: channel.inbox, user: agent)
    get "#{url}/management_events", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    foreign = create(:inbox)
    get "/api/v1/accounts/#{account.id}/inboxes/#{foreign.id}/management_events", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
