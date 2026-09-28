require 'rails_helper'

RSpec.describe 'Account feature restrictions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  {
    'agent_management' => 'agents',
    'team_management' => 'teams',
    'inbox_management' => 'inboxes',
    'labels' => 'labels',
    'custom_attributes' => 'custom_attribute_definitions',
    'automations' => 'automation_rules',
    'canned_responses' => 'canned_responses',
    'macros' => 'macros',
    'campaigns' => 'campaigns',
    'integrations' => 'integrations/hooks'
  }.each do |feature, endpoint|
    it "rejects creation through #{endpoint} when #{feature} is disabled" do
      account.disable_features!(feature)
      post "/api/v1/accounts/#{account.id}/#{endpoint}", headers: admin.create_new_auth_token, params: {}, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'keeps auxiliary team and agent lists available with management disabled' do
    account.disable_features!('team_management', 'agent_management', 'inbox_management')
    %w[teams agents inboxes].each do |endpoint|
      get "/api/v1/accounts/#{account.id}/#{endpoint}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  it 'rejects API inbox creation by channel flag without disabling inbox management' do
    account.disable_features!('channel_api')
    expect do
      post "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token,
                                                     params: { name: 'Restricted', channel: { type: 'api' } }, as: :json
    end.not_to change(account.inboxes, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'preserves existing API inbox updates when only new API channels are disabled' do
    inbox = create(:inbox, channel: create(:channel_api, account: account), account: account)
    account.disable_features!('channel_api')
    patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: admin.create_new_auth_token,
                                                                params: { name: 'Existing' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(inbox.reload.name).to eq('Existing')
  end

  it 'blocks the directory but preserves the contact sidebar of an accessible conversation' do
    inbox = create(:inbox, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    contact = create(:contact, :with_email, account: account)
    create(:conversation, inbox: inbox, account: account, contact: contact, assignee: agent)
    account.enable_features!('hide_contacts_for_agent')
    get "/api/v1/accounts/#{account.id}/contacts", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
  end

  it 'blocks direct access to another assignee conversation and its messages' do
    inbox = create(:inbox, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    conversation = create(:conversation, inbox: inbox, account: account, assignee: admin)
    account.enable_features!('hide_all_chats_for_agent')
    ["conversations/#{conversation.display_id}", "conversations/#{conversation.display_id}/messages"].each do |endpoint|
      get "/api/v1/accounts/#{account.id}/#{endpoint}", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'rejects deletion by an agent while retaining the sent message' do
    inbox = create(:inbox, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    conversation = create(:conversation, inbox: inbox, account: account, assignee: agent)
    message = create(:message, account: account, conversation: conversation, content: 'Keep me')
    account.enable_features!('hide_delete_message_for_agent')
    delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
           headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(message.reload.content).to eq('Keep me')
  end
end
