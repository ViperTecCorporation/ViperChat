require 'rails_helper'

RSpec.describe 'Message favorites', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation, content: 'Favorite text') }
  let(:headers) { user.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/message_favorites" }

  it 'requires authentication' do
    get url
    expect(response).to have_http_status(:unauthorized)
  end

  it 'favorites text idempotently and removes it without deleting the message' do
    2.times { post url, headers: headers, params: { message_id: message.id }, as: :json }
    expect(response).to have_http_status(:ok)
    expect(MessageFavorite.where(user: user, message: message).count).to eq(1)
    delete "#{url}/#{message.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(message.reload.content).to eq('Favorite text')
    expect(MessageFavorite.where(user: user).count).to eq(0)
  end

  it 'lists the current original text and media, scoped to the contact' do
    attachment = message.attachments.create!(
      account: account, file_type: :image,
      file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
    )
    MessageFavorite.create!(user: user, account: account, message: message)
    message.update!(content: 'Edited text')
    get url, headers: headers, params: { contact_id: conversation.contact_id }, as: :json
    expect(response).to have_http_status(:ok)
    item = response.parsed_body['payload'].first['message']
    expect(item['content']).to eq('Edited text')
    expect(item['attachments'].first['id']).to eq(attachment.id)
    expect(item['conversation_id']).to eq(conversation.display_id)
    get url, headers: headers, params: { contact_id: create(:contact, account: account).id }, as: :json
    expect(response.parsed_body['payload']).to eq([])
  end

  it 'keeps favorites personal and isolated by account' do
    MessageFavorite.create!(user: user, account: account, message: message)
    other = create(:user, account: account, role: :administrator)
    get url, headers: other.create_new_auth_token
    expect(response.parsed_body['payload']).to eq([])
    foreign_message = create(:message)
    post url, headers: headers, params: { message_id: foreign_message.id }, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'does not expose favorites after inbox access is removed' do
    agent = create(:user, account: account, role: :agent)
    MessageFavorite.create!(user: agent, account: account, message: message)
    get url, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload']).to eq([])
    post url, headers: agent.create_new_auth_token, params: { message_id: message.id }, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'returns only ids for the requested conversation' do
    MessageFavorite.create!(user: user, account: account, message: message)
    get url, headers: headers, params: { conversation_id: conversation.display_id, ids_only: true }, as: :json
    expect(response.parsed_body['ids']).to eq([message.id])
  end

  it 'paginates without duplicating favorites' do
    messages = create_list(:message, 26, account: account, conversation: conversation)
    messages.each { |item| MessageFavorite.create!(user: user, account: account, message: item) }
    get url, headers: headers
    first_page = response.parsed_body
    expect(first_page['payload'].size).to eq(25)
    expect(first_page['has_more']).to be(true)
    get url, headers: headers, params: { before: first_page['payload'].last['id'] }, as: :json
    expect(response.parsed_body['payload'].size).to eq(1)
    expect(response.parsed_body['has_more']).to be(false)
  end

  it 'returns the selected message and nearby messages for navigation' do
    create_list(:message, 25, account: account, conversation: conversation)
    target = message
    create_list(:message, 25, account: account, conversation: conversation)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
        headers: headers, params: { around: target.id }, as: :json
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body['payload'].pluck('id')
    expect(ids.size).to eq(41)
    expect(ids[20]).to eq(target.id)
  end
end
