require 'rails_helper'

RSpec.describe 'Scheduled Messages API', type: :request do
  let!(:account) { create(:account) }
  let!(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'unoapi',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let!(:contact) { create(:contact, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: channel.inbox) }
  let!(:conversation) do
    create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let!(:label) { create(:label, account: account) }
  let!(:agent) { create(:user, account: account) }
  let(:audio_blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('audio data'),
      filename: 'voice.mp3',
      content_type: 'audio/mpeg'
    )
  end
  let(:messages) do
    [
      { content: 'First', content_type: 'text', attachment_blob_ids: [] },
      { content: nil, content_type: 'text', voice_message: true, attachment_blob_ids: [audio_blob.signed_id] },
      { content: 'Third', content_type: 'text', attachment_blob_ids: [] }
    ]
  end
  let(:params) do
    {
      conversation_id: conversation.display_id,
      scheduled_message: {
        scheduled_at: 1.hour.from_now.iso8601,
        label_id: label.id,
        sender_id: agent.id,
        messages: messages
      }
    }
  end

  before do
    create(:inbox_member, inbox: channel.inbox, user: agent)
  end

  it 'creates one schedule containing an ordered message sequence' do
    expect do
      post "/api/v1/accounts/#{account.id}/scheduled_messages",
           params: params,
           headers: agent.create_new_auth_token,
           as: :json
    end.to change(ScheduledMessage, :count).by(1).and change(ScheduledMessageItem, :count).by(3)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['message_count']).to eq(3)
    expect(response.parsed_body['messages'].pluck('content')).to eq(['First', nil, 'Third'])
    expect(response.parsed_body['messages'][1]['voice_message']).to be(true)
  end

  it 'rejects a sequence with more than five messages' do
    params[:scheduled_message][:messages] = Array.new(6) { |index| { content: "Message #{index}", content_type: 'text' } }

    expect do
      post "/api/v1/accounts/#{account.id}/scheduled_messages",
           params: params,
           headers: agent.create_new_auth_token,
           as: :json
    end.not_to change(ScheduledMessage, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects scheduling in a conversation the agent cannot access' do
    restricted_agent = create(:user, account: account)
    params[:scheduled_message][:sender_id] = restricted_agent.id

    post "/api/v1/accounts/#{account.id}/scheduled_messages",
         params: params,
         headers: restricted_agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
