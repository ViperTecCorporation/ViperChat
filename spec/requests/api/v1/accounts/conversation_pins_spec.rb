require 'rails_helper'

RSpec.describe 'Personal conversation pins', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:headers) { user.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/pin" }

  it 'requires authentication' do
    post url, params: { pinned: true }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'pins and unpins using the account-scoped display id' do
    post url, headers: headers, params: { pinned: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['pinned_conversations']).to eq([conversation.display_id])
    post url, headers: headers, params: { pinned: false }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['pinned_conversations']).to eq([])
  end

  it 'rejects a fourth pin with a specific error' do
    service = Conversations::PinService.new(user, account)
    create_list(:conversation, 3, account: account).each { |item| service.update(item, true) }
    post url, headers: headers, params: { pinned: true }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('pin_limit_reached')
  end

  it 'does not let a user pin conversations from another account' do
    stranger = create(:user)
    post url, headers: stranger.create_new_auth_token, params: { pinned: true }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(stranger.reload.ui_settings['pinned_conversations']).to be_nil
  end

  it 'returns old pinned conversations first on the first page' do
    Conversations::PinService.new(user, account).update(conversation, true)
    create(:conversation, account: account, last_activity_at: 1.hour.from_now)
    get "/api/v1/accounts/#{account.id}/conversations", headers: headers,
                                                        params: { status: 'all', assignee_type: 'all', sort_by: 'created_at_desc' },
                                                        as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'payload', 0, 'id')).to eq(conversation.display_id)
  end

  it 'denies an agent without access to the inbox' do
    agent = create(:user, account: account, role: :agent)
    post url, headers: agent.create_new_auth_token, params: { pinned: true }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(agent.reload.ui_settings['pinned_conversations']).to be_nil
  end
end
