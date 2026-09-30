require 'rails_helper'

RSpec.describe 'Gmail API authorization', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:state) do
    Rails.application.message_verifier('gmail-history').generate(
      { 'account_state' => account.to_sgid(expires_in: 15.minutes).to_s, 'gmail_transport' => 'api' }, expires_in: 15.minutes
    )
  end
  let(:token_response) do
    { id_token: JWT.encode({ email: 'gmail-review@example.com', name: 'Review' }, nil, 'none'),
      access_token: 'test-access', refresh_token: 'test-refresh', scope: Google::GmailClient::SCOPES.join(' ') }
  end

  before do
    stub_request(:post, 'https://accounts.google.com/o/oauth2/token')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: token_response.to_json)
  end

  it 'requests only read/send mail scopes and signs the transport even without history options' do
    create(:installation_config, name: 'GOOGLE_GMAIL_API_ENABLED', value: true)
    post "/api/v1/accounts/#{account.id}/google/authorization", headers: admin.create_new_auth_token
    query = CGI.parse(URI.parse(response.parsed_body['url']).query)
    expect(query['scope'].first.split).to eq(['email', 'profile'] + Google::GmailClient::SCOPES)
    data = Rails.application.message_verifier('gmail-history').verified(query['state'].first)
    expect(data['gmail_transport']).to eq('api')
  end

  it 'uses the signed selection even if the global default is disabled before callback' do
    create(:installation_config, name: 'GOOGLE_GMAIL_API_ENABLED', value: false)
    get '/google/callback', params: { code: 'test', state: state }
    expect(response).to have_http_status(:redirect)
    expect(account.inboxes.last.channel.gmail_api?).to be(true)
    expect(account.inboxes.last.channel.provider_config['receive_since']).to be_present
  end

  it 'rejects partial consent before creating an inbox' do
    token_response[:scope] = Google::GmailClient::SCOPES.first
    stub_request(:post, 'https://accounts.google.com/o/oauth2/token')
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: token_response.to_json)
    expect { get '/google/callback', params: { code: 'test', state: state } }.not_to(change { account.inboxes.count })
    expect(response).to redirect_to('/')
  end

  it 'preserves a legacy channel when the global default changes' do
    channel = create(:channel_email, provider: 'google', account: account)
    create(:installation_config, name: 'GOOGLE_GMAIL_API_ENABLED', value: true)
    expect(channel.reload.gmail_api?).to be(false)
  end

  it 'switches an existing channel only on explicit OAuth reconnection' do
    channel = create(:channel_email, provider: 'google', account: account, imap_login: 'gmail-review@example.com')
    get '/google/callback', params: { code: 'test', state: state }
    expect(channel.reload.gmail_api?).to be(true)
    expect(account.inboxes.count).to eq(1)
  end
end
