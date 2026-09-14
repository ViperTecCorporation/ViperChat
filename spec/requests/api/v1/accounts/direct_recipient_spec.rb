require 'rails_helper'

RSpec.describe 'Direct WhatsApp recipient', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false) }
  let(:params) do
    { inbox_id: channel.inbox.id, recipient: { phone_number: '66996222472' }, message: { content: 'Hello' }, assignee_id: user.id }
  end

  it 'creates the contact, conversation and message together' do
    post "/api/v1/accounts/#{account.id}/conversations", params: params, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    contact = account.contacts.find_by!(phone_number: '+5566996222472')
    expect(contact.conversations.last.messages.last.content).to eq('Hello')
    post "/api/v1/accounts/#{account.id}/conversations", params: params, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(account.contacts.where(phone_number: '+5566996222472').count).to eq(1)
  end

  it 'rolls back the contact when message validation fails' do
    params[:message][:content] = 'a' * 160_000
    post "/api/v1/accounts/#{account.id}/conversations", params: params, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.contacts.where(phone_number: '+5566996222472')).not_to exist
  end
end
