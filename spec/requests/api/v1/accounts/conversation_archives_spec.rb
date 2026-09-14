require 'rails_helper'

RSpec.describe 'Personal conversation archives', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account, assignee: user, status: :open).reload }
  let(:headers) { user.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/conversations" }
  let(:service) { Conversations::ArchiveService.new(user, account) }

  it 'requires login' do
    post "#{base}/#{conversation.display_id}/archive", params: { archived: true }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'archives and restores without changing status or assignment' do
    2.times { post "#{base}/#{conversation.display_id}/archive", headers: headers, params: { archived: true }, as: :json }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['archived_conversations']).to eq([conversation.display_id])
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: user.id)
    post "#{base}/#{conversation.display_id}/archive", headers: headers, params: { archived: false }, as: :json
    expect(response.parsed_body['archived_conversations']).to eq([])
  end

  it 'denies archiving an unassigned conversation even to administrators' do
    conversation.update!(assignee: nil)
    post "#{base}/#{conversation.display_id}/archive", headers: headers, params: { archived: true }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(service.ids).to eq([])
  end

  it 'denies archiving a conversation assigned to another agent' do
    conversation.update!(assignee: create(:user, account: account))
    post "#{base}/#{conversation.display_id}/archive", headers: headers, params: { archived: true }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'hides archived conversations and counts from mine but keeps an authorized archive list' do
    service.update(conversation, true)
    get base, headers: headers, params: { assignee_type: 'me', status: 'all' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'payload')).to eq([])
    expect(response.parsed_body.dig('data', 'meta', 'mine_count')).to eq(0)
    get "#{base}/archived", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([conversation.display_id])
  end

  it 'keeps archives personal and rejects profile API tampering' do
    service.update(conversation, true)
    other = create(:user, account: account, role: :administrator)
    get "#{base}/archived", headers: other.create_new_auth_token
    expect(response.parsed_body['payload']).to eq([])
    put '/api/v1/profile', headers: headers, params: { ui_settings: { archived_conversations: {} } }, as: :json
    expect(response).to have_http_status(:ok)
    user.reload
    expect(service.ids).to eq([conversation.display_id])
  end

  it 'blocks ordinary message notifications until restored' do
    service.update(conversation, true)
    message = create(:message, account: account, conversation: conversation)
    expect do
      NotificationBuilder.new(notification_type: 'assigned_conversation_new_message', user: user, account: account,
                              primary_actor: conversation, secondary_actor: message).perform
    end.not_to change(Notification, :count)
    expect(service.ids).to eq([conversation.display_id])
    service.update(conversation, false)
    expect do
      NotificationBuilder.new(notification_type: 'assigned_conversation_new_message', user: user, account: account,
                              primary_actor: conversation, secondary_actor: message).perform
    end.to change(Notification, :count).by(1)
  end

  it 'checks current archive state before delivering previously queued push and email' do
    notification = create(:notification, account: account, user: user, primary_actor: conversation)
    push = Notification::PushNotificationService.new(notification: notification)
    email = Notification::EmailNotificationService.new(notification: notification)
    service.update(conversation, true)
    expect(push).not_to receive(:notification_subscriptions)
    expect(email).not_to receive(:send_notification_email)
    push.perform
    email.perform
  end

  it 'does not mute another users notifications' do
    service.update(conversation, true)
    other = create(:user, account: account, role: :administrator)
    expect(Conversations::ArchiveService.archived?(other, conversation)).to be(false)
  end
end
