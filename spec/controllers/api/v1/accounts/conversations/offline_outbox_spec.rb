require 'rails_helper'

RSpec.describe 'Offline text outbox', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:url) { api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id) }
  let(:key) { SecureRandom.uuid }
  let(:payload) { { content: 'SYNTHETIC offline text', private: true, client_message_id: key, echo_id: "outbox-#{key}", content_type: 'text' } }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'returns the same ID after the first response is lost, including after record reload' do
    get api_v1_account_conversation_url(account_id: account.id, id: conversation.display_id), headers: headers, as: :json
    expect(response.parsed_body['offline_outbox_version']).to eq(1)
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:success)
    first_id = response.parsed_body['id']
    expect(conversation.messages.last.sender).to eq(agent)
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.values_at('id', 'echo_id')).to eq([first_id, "outbox-#{key}"])
    expect(conversation.messages.count).to eq(1)
    expect(conversation.messages.last.reload.content_attributes['client_message_id']).to eq(key)
  end

  it 'rejects reuse for different text instead of creating another message' do
    post url, params: payload, headers: headers, as: :json
    post url, params: payload.merge(content: 'different'), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.messages.count).to eq(1)
  end

  it 'keeps the idempotency identity after deleting an accepted message' do
    agent.account_users.find_by!(account: account).update!(role: :administrator)
    post url, params: payload, headers: headers, as: :json
    id = response.parsed_body['id']
    delete "#{url}/#{id}", headers: headers, as: :json
    expect(response).to have_http_status(:success)
    post url, params: payload, headers: headers, as: :json
    expect(response.parsed_body['id']).to eq(id)
    expect(conversation.messages.count).to eq(1)
    expect(conversation.messages.last.content_attributes['deleted']).to be(true)
  end

  it 'keeps the idempotency identity after the existing retry action' do
    post url, params: payload, headers: headers, as: :json
    id = response.parsed_body['id']
    post "#{url}/#{id}/retry", headers: headers, as: :json
    expect(response).to have_http_status(:success)
    post url, params: payload, headers: headers, as: :json
    expect(response.parsed_body['id']).to eq(id)
    expect(conversation.messages.count).to eq(1)
  end

  it 'does not bypass revoked inbox access on a duplicate retry' do
    post url, params: payload, headers: headers, as: :json
    inbox.inbox_members.destroy_all
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(conversation.messages.count).to eq(1)
  end

  it 'does not deduplicate different user intentions with identical text' do
    post url, params: payload, headers: headers, as: :json
    post url, params: payload.merge(client_message_id: SecureRandom.uuid), headers: headers, as: :json
    expect(response).to have_http_status(:success)
    expect(conversation.messages.count).to eq(2)
  end

  it 'preserves private notes, reply IDs and text through the existing builder' do
    original = create(:message, conversation: conversation, account: account, inbox: inbox)
    post url, params: payload.merge(content_attributes: { in_reply_to: original.id }), headers: headers, as: :json
    expect(response).to have_http_status(:success)
    saved = conversation.messages.last
    expect(saved).to be_private
    expect(saved.content).to eq('SYNTHETIC offline text')
    expect(saved.content_attributes['in_reply_to']).to eq(original.id)
  end

  it 'rejects invalid keys, attachments and unsupported templates without creating anything' do
    post url, params: payload.merge(client_message_id: 'invalid'), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post url, params: payload.merge(template_params: { name: 'test' }), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post url, params: payload.merge(attachments: ['invalid']), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.messages.count).to eq(0)
  end
end
