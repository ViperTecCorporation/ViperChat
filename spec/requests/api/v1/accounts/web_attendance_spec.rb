require 'rails_helper'

RSpec.describe 'Agent web attendance controls', type: :request do
  include_context 'with Uno web attendance'

  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/web_attendance" }
  let(:headers) { user.create_new_auth_token }

  context 'with WhatsApp Cloud' do
    before do
      channel.update!(provider: 'whatsapp_cloud')
      inbox.update!(web_attendance_button_text: 'Abrir atendimento')
      conversation.reload
      create(:message, account: account, conversation: conversation, sender: contact, created_at: 1.hour.ago)
    end

    it 'returns the provider limits and open window permission' do
      get url, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'provider' => 'whatsapp_cloud', 'can_invite' => true, 'invitation_max_length' => 1024, 'button_max_length' => 20
      )
    end

    it 'blocks creation and manual fallback after the window expires' do
      invitation_message.update!(status: :failed)
      travel 25.hours do
        get url, headers: headers
        expect(response.parsed_body['enabled']).to be(true)
        expect(response.parsed_body['can_invite']).to be(false)
        expect do
          post url, headers: headers, params: { request_id: 'closed-cloud-window', content: 'Continue here' }
        end.not_to change(WebAttendanceInvitation, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        post "#{url}/fallback", headers: headers, params: { invitation_id: invitation.id }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(invitation_message.reload.content_attributes['web_attendance_text_fallback']).not_to be(true)
      end
    end

    it 'rejects an oversized Cloud default without saving it' do
      params = { web_attendance_invitation_message: 'a' * 1025 }
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: headers, params: params
      expect(response).to have_http_status(:unprocessable_entity)
      expect(inbox.reload.web_attendance_invitation_message).to eq('')
    end
  end

  it 'persists and returns the inbox default invitation message' do
    params = { web_attendance_invitation_message: 'Continue com nossa equipe aqui.' }
    patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: headers, params: params
    expect(response).to have_http_status(:ok)
    expect(inbox.reload.web_attendance_invitation_message).to eq('Continue com nossa equipe aqui.')
    expect(response.parsed_body['web_attendance_invitation_message']).to eq('Continue com nossa equipe aqui.')
  end

  it 'rejects an oversized inbox invitation message without changing the saved default' do
    inbox.update!(web_attendance_invitation_message: 'Keep this invitation')
    params = { web_attendance_invitation_message: 'a' * 4097 }
    patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: headers, params: params
    expect(response).to have_http_status(:unprocessable_entity)
    expect(inbox.reload.web_attendance_invitation_message).to eq('Keep this invitation')
  end

  ['image/png', 'audio/ogg', 'video/mp4', 'application/pdf'].each do |mime_type|
    it "keeps multipart #{mime_type} from an agent public, outgoing and Web-only" do
      upload = Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/sample.pdf'), mime_type)
      expect(SendReplyJob).not_to receive(:perform_later)
      params = { private: 'false', delivery_destination: 'web', attachments: [upload] }
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages", headers: headers, params: params
      expect(response).to have_http_status(:ok)
      message = Message.find(response.parsed_body['id'])
      expect(message).to be_outgoing
      expect(message).not_to be_private
      expect(message).to have_attributes(sender_type: 'User', sender_id: user.id)
      expect(message.delivery_destination).to eq('web')
      expect(WebAttendance::MessagePresenter.new(message).as_json[:message_type]).to eq(1)
    end
  end

  it 'rejects manual retries of automatic absence reminders' do
    invitation.activate!
    reminder = create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing,
                                content_attributes: { web_absence_request_key: 'test-episode' })
    expect(SendReplyJob).not_to receive(:perform_later)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{reminder.id}/retry", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'marks fetched visitor messages delivered without acknowledging WhatsApp or marking them read' do
    invitation.activate!
    web = create(:message, account: account, conversation: conversation, sender: contact, delivery_destination: 'web', status: :sent)
    whatsapp = create(:message, account: account, conversation: conversation, sender: contact, status: :sent)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages", headers: headers
    expect(response).to have_http_status(:ok)
    expect(web.reload).to be_delivered
    expect(whatsapp.reload).to be_sent
    post "#{url}/seen", headers: headers, params: { destination: 'web' }
    expect(web.reload).to be_read
    expect(whatsapp.reload).to be_sent
  end

  it 'requires agent authentication' do
    get url
    expect(response).to have_http_status(:unauthorized)
  end

  it 'prevents another account from reading state or creating an invitation' do
    other = create(:user, account: create(:account), role: :administrator)
    other_headers = other.create_new_auth_token
    get url, headers: other_headers
    expect(response).to have_http_status(:unauthorized)
    expect do
      post url, headers: other_headers, params: { request_id: 'foreign-request-001', content: 'Foreign' }
    end.not_to change(WebAttendanceInvitation, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'creates a manual invitation without exposing its plaintext token in the agent response' do
    post url, headers: headers, params: { request_id: 'agent-request-001', content: 'Continue here' }
    expect(response).to have_http_status(:ok)
    record = conversation.web_attendance_invitations.last
    expect(record.message.content).to eq('Continue here')
    expect(response.body).not_to include(record.link.split('#token=').last)
    expect(record).not_to be_active
  end

  it 'deduplicates manual invitation requests' do
    post url, headers: headers, params: { request_id: 'agent-request-001', content: 'Continue here' }
    id = response.parsed_body['message']['id']
    expect do
      post url, headers: headers, params: { request_id: 'agent-request-001', content: 'Retry' }
    end.not_to change(WebAttendanceInvitation, :count)
    expect(response.parsed_body['message']['id']).to eq(id)
  end

  it 'revokes both links and sessions without deleting chat history' do
    invitation.activate!
    session = invitation.web_attendance_sessions.create!(token_digest: Digest::SHA256.hexdigest('session'))
    history = create(:message, account: account, conversation: conversation, sender: contact, delivery_destination: 'web')
    delete url, headers: headers
    expect(response).to have_http_status(:no_content)
    expect(invitation.reload).not_to be_active
    expect(session.reload).not_to be_active
    expect(Message.exists?(history.id)).to be(true)
  end

  it 'tracks unread counts and read acknowledgements independently for each destination' do
    channel_message = create(:message, account: account, conversation: conversation, sender: contact)
    web_message = create(:message, account: account, conversation: conversation, sender: contact, delivery_destination: 'web')
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['unread']).to eq('channel' => 1, 'web' => 1)
    post "#{url}/seen", headers: headers, params: { destination: 'web' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['unread']).to eq('channel' => 1, 'web' => 0)
    expect(web_message.reload).to be_read
    expect(channel_message.reload).not_to be_read
  end

  it 'requires explicit fallback and puts the secret link only in the transient Uno request' do
    invitation_message.update!(status: :failed)
    post "#{url}/fallback", headers: headers, params: { invitation_id: invitation.id }
    expect(response).to have_http_status(:accepted)
    expect(invitation_message.reload.content_attributes['web_attendance_text_fallback']).to be(true)
    request = stub_request(:post, 'https://uno.example.com/v13.0/556600000000/messages').with do |outgoing|
      body = JSON.parse(outgoing.body)
      body['type'] == 'text' && body.dig('text', 'body') == "Continue on the web\n#{invitation.link}"
    end.to_return(status: 200, body: { messages: [{ id: 'uno-fallback-001' }] }.to_json,
                  headers: { 'Content-Type' => 'application/json' })
    SendReplyJob.perform_now(invitation_message.id)
    expect(request).to have_been_requested.once
    expect(invitation.reload).to be_active
    expect(invitation_message.reload.attributes.to_json).not_to include(invitation_token)
  end
end
