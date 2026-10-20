require 'rails_helper'

RSpec.describe 'Agent label creation', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:params) { { label: { title: 'agent-created', color: '#123456' } } }

  it 'rejects agent creation by default' do
    expect { post "/api/v1/accounts/#{account.id}/labels", params: params, headers: agent.create_new_auth_token, as: :json }
      .not_to change(Label, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows agent creation when explicitly enabled' do
    account.update!(allow_agents_to_create_labels: true)
    expect { post "/api/v1/accounts/#{account.id}/labels", params: params, headers: agent.create_new_auth_token, as: :json }
      .to change(account.labels, :count).by(1)
    expect(response).to have_http_status(:success)
  end

  it 'keeps administrator creation independent of the preference' do
    expect { post "/api/v1/accounts/#{account.id}/labels", params: params, headers: admin.create_new_auth_token, as: :json }
      .to change(account.labels, :count).by(1)
  end

  it 'does not grant agents editing or deletion' do
    account.update!(allow_agents_to_create_labels: true)
    label = create(:label, account: account)
    put "/api/v1/accounts/#{account.id}/labels/#{label.id}", params: { label: { title: 'changed' } },
                                                             headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(label.reload.title).not_to eq('changed')
    expect { delete "/api/v1/accounts/#{account.id}/labels/#{label.id}", headers: agent.create_new_auth_token, as: :json }
      .not_to change(Label, :count)
  end

  it 'only allows administrators to change the preference' do
    patch "/api/v1/accounts/#{account.id}", params: { allow_agents_to_create_labels: true }, headers: agent.create_new_auth_token, as: :json
    expect(account.reload.allow_agents_to_create_labels).not_to be(true)
    patch "/api/v1/accounts/#{account.id}", params: { allow_agents_to_create_labels: true }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(account.reload.allow_agents_to_create_labels).to be(true)
  end

  it 'does not grant creation in another account' do
    other_account = create(:account, allow_agents_to_create_labels: true)
    expect { post "/api/v1/accounts/#{other_account.id}/labels", params: params, headers: agent.create_new_auth_token, as: :json }
      .not_to change(Label, :count)
  end
end
