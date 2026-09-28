require 'rails_helper'

RSpec.describe 'Google email history', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_email, provider: 'google', account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/google/email_history" }

  it 'starts and stops an import without exposing credentials' do
    post url, headers: admin.create_new_auth_token, params: { inbox_id: channel.inbox.id, period: '6m' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['status']).to eq('running')
    expect(response.parsed_body).not_to have_key('access_token')
    delete url, headers: admin.create_new_auth_token, params: { inbox_id: channel.inbox.id }, as: :json
    expect(response.parsed_body['status']).to eq('stopped')
  end

  it 'rejects more than twelve months' do
    post url, headers: admin.create_new_auth_token, params: { inbox_id: channel.inbox.id, period: '13m' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects agents and inboxes from other accounts' do
    agent = create(:user, account: account, role: :agent)
    post url, headers: agent.create_new_auth_token, params: { inbox_id: channel.inbox.id, period: '7d' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    other = create(:channel_email, provider: 'google')
    get url, headers: admin.create_new_auth_token, params: { inbox_id: other.inbox.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'carries the period in an expiring signed OAuth state' do
    post "/api/v1/accounts/#{account.id}/google/authorization", headers: admin.create_new_auth_token,
                                                                params: { history_period: '12m' }, as: :json
    expect(response).to have_http_status(:ok)
    state = CGI.parse(URI.parse(response.parsed_body['url']).query)['state'].first
    data = Rails.application.message_verifier('gmail-history').verified(state)
    expect(data['period']).to eq('12m')
    expect(GlobalID::Locator.locate_signed(data['account_state'])).to eq(account)
  end

  it 'applies signed history settings after the Google callback' do
    state = Rails.application.message_verifier('gmail-history').generate(
      { 'account_state' => account.to_sgid(expires_in: 15.minutes).to_s, 'period' => '12m' }, expires_in: 15.minutes
    )
    stub_request(:post, 'https://accounts.google.com/o/oauth2/token').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id_token: JWT.encode({ email: 'history@example.com', name: 'History' }, nil, 'none'),
              access_token: 'test-access', refresh_token: 'test-refresh' }.to_json
    )
    get '/google/callback', params: { code: 'test', state: state }
    imported = account.inboxes.last.channel
    expect(imported.provider_config.dig('email_history', 'period')).to eq('12m')
    expect(imported.provider_config['receive_since']).to be_present
    expect(imported.provider_config['access_token']).to eq('test-access')
  end
end
