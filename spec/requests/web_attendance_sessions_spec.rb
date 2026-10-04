require 'rails_helper'

RSpec.describe 'Web attendance guest sessions', type: :request do
  include_context 'with Uno web attendance'

  let(:guest_headers) { { 'X-Web-Attendance' => '1' } }

  around do |example|
    original = Rails.application.env_config['action_dispatch.show_exceptions']
    Rails.application.env_config['action_dispatch.show_exceptions'] = :none
    example.run
  ensure
    Rails.application.env_config['action_dispatch.show_exceptions'] = original
  end

  describe 'invitation exchange' do
    it 'rejects invalid and unactivated links without creating a session' do
      post '/web-attendance/api/session', params: { token: 'unknown-token' }, headers: guest_headers
      expect(response).to have_http_status(:gone)
      post '/web-attendance/api/session', params: { token: invitation_token }, headers: guest_headers
      expect(response).to have_http_status(:gone)
      expect(invitation.web_attendance_sessions).to be_empty
    end

    it 'requires the same-origin custom header before exchanging a token' do
      invitation.activate!
      post '/web-attendance/api/session', params: { token: invitation_token }
      expect(response).to have_http_status(:forbidden)
      expect(invitation.web_attendance_sessions).to be_empty
    end

    it 'creates a hashed session and an HTTP-only restricted cookie without returning secrets' do
      invitation.activate!
      post '/web-attendance/api/session', params: { token: invitation_token }, headers: guest_headers
      expect(response).to have_http_status(:created)
      expect(invitation.web_attendance_sessions.count).to eq(1)
      expect(invitation.web_attendance_sessions.first.token_digest).to match(/\A[0-9a-f]{64}\z/)
      expect(response.body).not_to include(invitation_token)
      expect(response.headers['Set-Cookie']).to include('httponly', 'samesite=strict', 'path=/web-attendance/api')
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.headers['Referrer-Policy']).to eq('no-referrer')
    end
  end

  context 'with an authenticated guest' do
    before do
      invitation.activate!
      post '/web-attendance/api/session', params: { token: invitation_token }, headers: guest_headers
    end

    it 'reports delivery only for fetched Web replies and read only after the visitor acknowledges' do
      reply = create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing,
                               delivery_destination: 'web', status: :sent)
      whatsapp = create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing, status: :sent)
      get '/web-attendance/api/session'
      expect(response).to have_http_status(:ok)
      data = response.parsed_body['messages'].find { |item| item['id'] == reply.id }
      expect(data['status']).to eq('delivered')
      expect(reply.reload).to be_delivered
      expect(whatsapp.reload).to be_sent
      post '/web-attendance/api/seen', headers: guest_headers
      expect(reply.reload).to be_read
      expect(whatsapp.reload).to be_sent
      get '/web-attendance/api/session'
      expect(response.parsed_body['messages'].find { |item| item['id'] == reply.id }['status']).to eq('read')
    end

    it 'exposes only current-cycle public history and never private content, other accounts or invite links' do
      current_account = Account.find(account.id)
      current_conversation = Conversation.find(conversation.id)
      old = create(:message, account: current_account, conversation: current_conversation, content: 'Previous cycle', created_at: 2.days.ago)
      private_message = create(:message, account: current_account, conversation: current_conversation, private: true, content: 'Private note')
      public_message = create(:message, account: current_account, conversation: current_conversation, content: 'Current WhatsApp message')
      web_message = create(:message, account: current_account, conversation: current_conversation, sender: Contact.find(contact.id),
                                     delivery_destination: 'web', content: 'Current Web message')
      foreign_message = create(:message, content: 'Foreign account secret')
      get '/web-attendance/api/session', params: { conversation_id: foreign_message.conversation_id, account_id: foreign_message.account_id }
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['messages'].pluck('id')
      expect(ids).to contain_exactly(public_message.id, web_message.id)
      expect(ids).not_to include(old.id, private_message.id, foreign_message.id, invitation_message.id)
      expect(response.body).not_to include('Private note', 'Previous cycle', 'Foreign account secret', invitation_token)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.headers['Referrer-Policy']).to eq('no-referrer')
    end

    it 'cannot use query parameters to send into another conversation or spoof the sender and destination' do
      foreign = create(:conversation)
      params = { request_id: 'guest-message-001', content: 'Web hello', conversation_id: foreign.id,
                 account_id: foreign.account_id, sender_id: user.id, delivery_destination: 'channel', private: true }
      post '/web-attendance/api/messages', headers: guest_headers, params: params
      expect(response).to have_http_status(:created)
      message = Message.find(response.parsed_body['id'])
      expect(message.conversation_id).to eq(conversation.id)
      expect(message.account_id).to eq(account.id)
      expect(message.attributes).to include('sender_type' => 'Contact', 'sender_id' => contact.id)
      expect(message.delivery_destination).to eq('web')
      expect(message).not_to be_private
      expect(foreign.messages.incoming).to be_empty
    end

    it 'deduplicates submitted messages by request id' do
      post '/web-attendance/api/messages', headers: guest_headers, params: { request_id: 'guest-message-001', content: 'Original' }
      id = response.parsed_body['id']
      expect do
        post '/web-attendance/api/messages', headers: guest_headers, params: { request_id: 'guest-message-001', content: 'Retry' }
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('id' => id, 'content' => 'Original')
    end

    it 'does not return previous-cycle content when a guest reuses the same request id after reopening' do
      old = create(:message, account: account, conversation: conversation, sender: contact, delivery_destination: 'web',
                             content: 'Previous cycle secret', content_attributes: { web_request_id: 'reused-request-001' })
      conversation.resolved!
      conversation.open!
      replacement = invitation_service.create!(content: 'New cycle invite', request_id: 'invite-next-cycle')
      record = conversation.web_attendance_invitations.find_by!(message: replacement)
      record.activate!
      post '/web-attendance/api/session', params: { token: record.link.split('#token=').last }, headers: guest_headers
      post '/web-attendance/api/messages', headers: guest_headers, params: { request_id: 'reused-request-001', content: 'Current cycle content' }
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['id']).not_to eq(old.id)
      expect(response.parsed_body['content']).to eq('Current cycle content')
      expect(response.body).not_to include('Previous cycle secret')
      expect(Message.find(response.parsed_body['id']).id).to be >= conversation.web_attendance_start_message_id
    end

    it 'rejects empty messages and attachment references instead of accepting unsigned blob ids' do
      post '/web-attendance/api/messages', headers: guest_headers, params: { request_id: 'guest-message-001', content: '' }
      expect(response).to have_http_status(:unprocessable_entity)
      post '/web-attendance/api/messages', headers: guest_headers, params: { request_id: 'guest-message-002', attachments: ['forged-blob-id'] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.messages.where(delivery_destination: 'web')).to be_empty
    end

    it 'accepts multipart image uploads and exposes only a session-protected URL' do
      upload = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')
      post '/web-attendance/api/messages', headers: guest_headers, params: { request_id: 'guest-message-001', attachments: [upload] }
      expect(response).to have_http_status(:created)
      attachment = Message.find(response.parsed_body['id']).attachments.first
      expect(response.parsed_body['attachments'].first['url']).to eq("/web-attendance/api/attachments/#{attachment.id}")
      expect(response.body).not_to include('/rails/active_storage', 'signed_id')
      get "/web-attendance/api/attachments/#{attachment.id}"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/png')
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    end

    it 'does not disclose quoted private or previous-cycle messages' do
      secret = create(:message, account: account, conversation: conversation, private: true, content: 'Quoted secret')
      old = create(:message, account: account, conversation: conversation, content: 'Old quoted secret', created_at: 2.days.ago)
      create(:message, account: account, conversation: conversation, content: 'Public reply',
                       content_attributes: { in_reply_to: secret.id, quoted_content: secret.content })
      create(:message, account: account, conversation: conversation, content: 'Another public reply',
                       content_attributes: { in_reply_to: old.id, quoted_content: old.content })
      get '/web-attendance/api/session'
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Quoted secret', 'Old quoted secret', 'quoted_content')
    end

    it 'serves an authorized byte range and rejects ranges beyond the file' do
      message = create(:message, :with_attachment, account: account, conversation: conversation)
      file = message.attachments.first.file
      get "/web-attendance/api/attachments/#{message.attachments.first.id}", headers: { 'Range' => 'bytes=0-9' }
      expect(response).to have_http_status(:partial_content)
      expect(response.body.bytesize).to eq(10)
      expect(response.headers['Content-Range']).to eq("bytes 0-9/#{file.blob.byte_size}")
      expect(response.headers['Cache-Control']).to include('no-store')
      get "/web-attendance/api/attachments/#{message.attachments.first.id}", headers: { 'Range' => 'bytes=999999999-' }
      expect(response).to have_http_status(:range_not_satisfiable)
    end

    it 'hides view-once media without consuming or deleting it after repeated downloads' do
      message = create(:message, :with_attachment,
                       account: account, conversation: conversation, sender: contact,
                       delivery_destination: 'web', content_attributes: { view_once: true })
      get '/web-attendance/api/session'
      item = response.parsed_body['messages'].find { |entry| entry['id'] == message.id }
      expect(item['view_once']).to be(true)
      2.times do
        get "/web-attendance/api/attachments/#{message.attachments.first.id}"
        expect(response).to have_http_status(:ok)
      end
      expect(message.attachments.first.file).to be_attached
    end

    it 'marks only Web outgoing messages as read' do
      whatsapp = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: user, status: :sent)
      web = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: user,
                             delivery_destination: 'web', status: :sent)
      post '/web-attendance/api/seen', headers: guest_headers
      expect(response).to have_http_status(:no_content)
      expect(web.reload).to be_read
      expect(whatsapp.reload).to be_sent
    end

    it 'refuses history, late submissions and downloads after resolution and after reopening' do
      message = create(:message, :with_attachment, account: account, conversation: conversation)
      conversation.resolved!
      get '/web-attendance/api/session'
      expect(response).to have_http_status(:gone)
      expect do
        post '/web-attendance/api/messages', headers: guest_headers, params: { request_id: 'late-message-001', content: 'Late' }
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:gone)
      expect(conversation.reload).to be_resolved
      get "/web-attendance/api/attachments/#{message.attachments.first.id}"
      expect(response).to have_http_status(:gone)
      conversation.open!
      get '/web-attendance/api/session'
      expect(response).to have_http_status(:gone)
      post '/web-attendance/api/session', params: { token: invitation_token }, headers: guest_headers
      expect(response).to have_http_status(:gone)
    end

    it 'invalidates the open browser session when the inbox is disabled' do
      inbox.update!(web_attendance_enabled: false)
      get '/web-attendance/api/session'
      expect(response).to have_http_status(:gone)
      post '/web-attendance/api/messages', headers: guest_headers, params: { request_id: 'late-message-001', content: 'Late' }
      expect(response).to have_http_status(:gone)
    end

    it 'excludes previous-cycle messages even when reopening happens in the same second' do
      freeze_time do
        previous = create(:message, account: account, conversation: conversation, content: 'Same second old content')
        conversation.resolved!
        conversation.open!
        current = create(:message, account: account, conversation: conversation, content: 'Same second new content')
        replacement = invitation_service.create!(content: 'New cycle invite', request_id: 'invite-next-cycle')
        record = conversation.web_attendance_invitations.find_by!(message: replacement)
        record.activate!
        post '/web-attendance/api/session', params: { token: record.link.split('#token=').last }, headers: guest_headers
        expect(response).to have_http_status(:created)
        get '/web-attendance/api/session'
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['messages'].pluck('id')).to include(current.id)
        expect(response.parsed_body['messages'].pluck('id')).not_to include(previous.id)
      end
    end

    it 'restricts a legacy conversation without a known cycle to content after the first invitation' do
      conversation.web_attendance_invitations.destroy_all
      conversation.update!(web_attendance_started_at: nil, web_attendance_start_message_id: nil)
      previous = create(:message, account: account, conversation: conversation, content: 'Legacy secret')
      replacement = invitation_service.create!(content: 'Legacy invite', request_id: 'legacy-first-invite')
      record = conversation.web_attendance_invitations.find_by!(message: replacement)
      record.activate!
      current = create(:message, account: account, conversation: conversation, content: 'After legacy invite')
      post '/web-attendance/api/session', params: { token: record.link.split('#token=').last }, headers: guest_headers
      expect(response).to have_http_status(:created)
      get '/web-attendance/api/session'
      expect(response.parsed_body['messages'].pluck('id')).to include(current.id)
      expect(response.parsed_body['messages'].pluck('id')).not_to include(previous.id)
    end

    it 'prevents downloading private, previous-cycle and foreign attachments by id' do
      private_message = create(:message, :with_attachment, account: account, conversation: conversation, private: true)
      old = create(:message, :with_attachment, account: account, conversation: conversation, created_at: 2.days.ago)
      foreign = create(:message, :with_attachment)
      [private_message, old, foreign].each do |message|
        get "/web-attendance/api/attachments/#{message.attachments.first.id}"
        expect(response).to have_http_status(:not_found)
        expect(response.headers['Cache-Control']).to include('no-store')
      end
    end
  end
end
