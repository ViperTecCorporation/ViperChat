require 'rails_helper'

RSpec.describe 'Web attendance presence', type: :request do
  include_context 'with Uno web attendance'

  let(:headers) { { 'X-Web-Attendance' => '1' } }

  it 'requires both the restricted session cookie and the custom header' do
    post '/web-attendance/api/presence', params: { visible: true }, headers: headers
    expect(response).to have_http_status(:gone)
    invitation.activate!
    post '/web-attendance/api/session', params: { token: invitation_token }, headers: headers
    post '/web-attendance/api/presence', params: { visible: true }
    expect(response).to have_http_status(:forbidden)
    expect(invitation.web_attendance_sessions.sole.presence_seen_at).to be_nil
  end

  context 'with an authenticated guest' do
    before do
      invitation.activate!
      post '/web-attendance/api/session', params: { token: invitation_token }, headers: headers
    end

    it 'accepts visibility without trusting client identity, timestamps or read state' do
      reply = create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing,
                               delivery_destination: 'web', status: :sent)
      post '/web-attendance/api/presence', params: { visible: true, conversation_id: -1, presence_seen_at: 1.year.from_now }, headers: headers
      expect(response).to have_http_status(:no_content)
      session = invitation.web_attendance_sessions.sole
      expect(session.visible).to be(true)
      expect(session.presence_seen_at).to be_within(2.seconds).of(Time.current)
      expect(reply.reload).to be_sent
      expect(response.headers['Cache-Control']).to eq('no-store')
      post '/web-attendance/api/presence', params: { visible: false }, headers: headers
      expect(response).to have_http_status(:no_content)
      expect(session.reload.visible).to be(false)
    end

    it 'rejects unspecified visibility and revoked sessions' do
      post '/web-attendance/api/presence', params: {}, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      post '/web-attendance/api/presence', params: { visible: true, presence_id: 'not-a-uuid' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      invitation.update!(revoked_at: Time.current)
      post '/web-attendance/api/presence', params: { visible: true }, headers: headers
      expect(response).to have_http_status(:gone)
    end

    it 'does not treat polling and seen as a visibility heartbeat' do
      get '/web-attendance/api/session'
      post '/web-attendance/api/seen', headers: headers
      expect(invitation.web_attendance_sessions.sole.presence_seen_at).to be_nil
      expect(conversation.reload.web_presence_online).to be(false)
    end
  end
end
