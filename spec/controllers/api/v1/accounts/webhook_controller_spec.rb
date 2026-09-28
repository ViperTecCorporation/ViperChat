require 'rails_helper'

RSpec.describe 'Webhooks API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:webhook) { create(:webhook, account: account, inbox: inbox, url: 'https://hello.com', name: 'My Webhook') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'creation-only restrictions on self-hosted accounts' do
    before do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)
      webhook
      account.disable_features!('api_and_webhooks')
    end

    it 'rejects new webhooks from the dashboard' do
      expect do
        post "/api/v1/accounts/#{account.id}/webhooks", headers: administrator.create_new_auth_token,
                                                        params: { url: 'https://new.example.com', subscriptions: ['message_created'] }, as: :json
      end.not_to change(Webhook, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects new webhooks using an existing API token without revoking its read access' do
      headers = { api_access_token: administrator.access_token.token }
      get "/api/v1/accounts/#{account.id}/webhooks", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post "/api/v1/accounts/#{account.id}/webhooks", headers: headers,
                                                      params: { url: 'https://new.example.com', subscriptions: ['message_created'] }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows updating and deleting an existing webhook' do
      put "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}", headers: administrator.create_new_auth_token,
                                                                   params: { name: 'Updated', url: 'https://updated.example.com' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(webhook.reload.url).to eq('https://updated.example.com')
      delete "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'enforces creation restrictions outside the controller as well' do
      new_hook = build(:webhook, account: account, inbox: inbox, url: 'https://new.example.com')
      expect(new_hook.save).to be false
      channel = build(:channel_api, account: account)
      expect(channel.save).to be false
      account.enable_features!('api_and_webhooks')
      expect(new_hook.save).to be true
      expect(channel.save).to be true
    end

    it 'preserves an existing API channel and its webhook URL' do
      account.enable_features!('api_and_webhooks')
      channel = create(:channel_api, account: account)
      account.disable_features!('api_and_webhooks')
      expect(channel.update(webhook_url: 'https://updated.example.com')).to be true
    end
  end

  describe 'GET /api/v1/accounts/<account_id>/webhooks' do
    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/webhooks",
            headers: agent.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin user' do
      it 'gets all webhook' do
        get "/api/v1/accounts/#{account.id}/webhooks",
            headers: administrator.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload']['webhooks'].count).to eql account.webhooks.count
      end
    end

    context 'when api_and_webhooks feature is disabled' do
      it 'allows session authenticated admins to manage webhooks' do
        allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
        account.disable_features!('api_and_webhooks')
        get "/api/v1/accounts/#{account.id}/webhooks",
            headers: administrator.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /api/v1/accounts/<account_id>/webhooks' do
    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             headers: agent.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin user' do
      it 'creates webhook' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { account_id: account.id, inbox_id: inbox.id, url: 'https://hello.com' },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:success)

        expect(response.parsed_body['payload']['webhook']['url']).to eql 'https://hello.com'
      end

      it 'creates webhook with name' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { account_id: account.id, inbox_id: inbox.id, url: 'https://hello.com', name: 'My Webhook' },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:success)

        expect(response.parsed_body['payload']['webhook']['name']).to eql 'My Webhook'
      end

      it 'throws error when invalid url provided' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { account_id: account.id, inbox_id: inbox.id, url: 'javascript:alert(1)' },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to eql 'Url is invalid'
      end

      it 'throws error if subscription events are invalid' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { url: 'https://hello.com', subscriptions: ['conversation_random_event'] },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to eql 'Subscriptions Invalid events'
      end

      it 'throws error if subscription events are empty' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { url: 'https://hello.com', subscriptions: [] },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to eql 'Subscriptions Invalid events'
      end

      it 'use default if subscription events are nil' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { url: 'https://hello.com', subscriptions: nil },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:ok)
        expect(
          response.parsed_body['payload']['webhook']['subscriptions']
        ).to eql %w[conversation_status_changed conversation_updated conversation_created contact_created contact_updated
                    message_created message_updated webwidget_triggered]
      end
    end
  end

  describe 'PUT /api/v1/accounts/<account_id>/webhooks/:id' do
    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
            headers: agent.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin user' do
      it 'updates webhook' do
        put "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
            params: { url: 'https://hello.com', name: 'Another Webhook' },
            headers: administrator.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload']['webhook']['url']).to eql 'https://hello.com'
        expect(response.parsed_body['payload']['webhook']['name']).to eql 'Another Webhook'
      end
    end
  end

  describe 'DELETE /api/v1/accounts/<account_id>/webhooks/:id' do
    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
               headers: agent.create_new_auth_token,
               as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin user' do
      it 'deletes webhook' do
        delete "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
               headers: administrator.create_new_auth_token,
               as: :json
        expect(response).to have_http_status(:success)
        expect(account.webhooks.count).to be 0
      end
    end
  end
end
