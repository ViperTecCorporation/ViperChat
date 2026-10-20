require 'rails_helper'

RSpec.describe 'Inbox insights API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/insights" }

  it 'requires authentication' do
    get url
    expect(response).to have_http_status(:unauthorized)
  end

  it 'denies cost analytics to an ordinary agent even with inbox access' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: channel.inbox, user: agent)
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not expose another account inbox' do
    other = create(:inbox)
    get "/api/v1/accounts/#{account.id}/inboxes/#{other.id}/insights", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects unsupported periods' do
    get url, headers: admin.create_new_auth_token, params: { days: 365 }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'returns informational data only for the authorized cloud inbox' do
    result = { informational_only: true, sections: {} }
    allow_any_instance_of(Whatsapp::AccountInsightsService).to receive(:perform).and_return(result)
    get url, headers: admin.create_new_auth_token, params: { days: 7 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(result.stringify_keys)
  end

  it 'rejects a ViperConnect channel without affecting its sending behavior' do
    channel.update!(provider: 'unoapi')
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:bad_request)
  end
end
