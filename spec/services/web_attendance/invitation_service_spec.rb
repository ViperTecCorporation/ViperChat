require 'rails_helper'

RSpec.describe WebAttendance::InvitationService do
  include_context 'with Uno web attendance'

  it 'stores a digest and recoverable ciphertext without putting the secret in message payloads' do
    expect(invitation.token_digest).to eq(Digest::SHA256.hexdigest(invitation_token))
    expect(invitation.encrypted_token).not_to include(invitation_token)
    expect(WebAttendanceInvitation.encryptor.decrypt_and_verify(invitation.encrypted_token)).to eq(invitation_token)
    expect(invitation_message.reload.attributes.to_json).not_to include(invitation_token)
    expect(invitation_message.push_event_data.to_json).not_to include(invitation_token)
    expect(invitation_message.webhook_data.to_json).not_to include(invitation_token)
    expect(invitation).not_to be_active
  end

  it 'deduplicates the request without creating another invitation or send job' do
    original = invitation_message
    expect do
      expect(invitation_service.create!(content: 'Duplicate', request_id: 'invite-request-001').id).to eq(original.id)
    end.not_to change(WebAttendanceInvitation, :count)
    expect(conversation.messages.with_content_attribute('web_invitation_request_id', 'invite-request-001').count).to eq(1)
  end

  it 'does not revoke a working invitation while a replacement awaits provider acceptance' do
    invitation.activate!
    replacement = invitation_service.create!(content: 'New invite', request_id: 'invite-request-002')
    expect(invitation.reload).to be_active
    expect(conversation.web_attendance_invitations.find_by!(message: replacement)).not_to be_active
  end

  it 'replaces the invitation and invalidates its sessions only when the new invitation activates' do
    invitation.activate!
    session = invitation.web_attendance_sessions.create!(token_digest: Digest::SHA256.hexdigest('old-session'))
    replacement = invitation_service.create!(content: 'New invite', request_id: 'invite-request-002')
    new_invitation = conversation.web_attendance_invitations.find_by!(message: replacement)
    expect(session).to be_active
    new_invitation.activate!
    expect(new_invitation.reload).to be_active
    expect(invitation.reload).not_to be_active
    expect(session.reload).not_to be_active
  end

  it 'permanently invalidates invitations and sessions across resolve and reopen' do
    invitation.activate!
    session = invitation.web_attendance_sessions.create!(token_digest: Digest::SHA256.hexdigest('old-session'))
    cycle = conversation.web_attendance_cycle
    conversation.resolved!
    expect(invitation.reload.revoked_at).to be_present
    expect(session.reload).not_to be_active
    conversation.open!
    expect(conversation.reload.web_attendance_cycle).to eq(cycle + 1)
    expect(invitation.reload).not_to be_active
    invitation.activate!
    expect(invitation.reload).not_to be_active
  end

  it 'does not reactivate old links after disabling and enabling the inbox' do
    invitation.activate!
    session = invitation.web_attendance_sessions.create!(token_digest: Digest::SHA256.hexdigest('old-session'))
    inbox.update!(web_attendance_enabled: false)
    expect(invitation.reload).not_to be_active
    expect(session.reload).not_to be_active
    inbox.update!(web_attendance_enabled: true)
    expect(invitation.reload).not_to be_active
  end

  it 'rejects invitations for resolved conversations' do
    conversation.resolved!
    expect { invitation_message }.to raise_error(ArgumentError, /unavailable/)
    expect(conversation.web_attendance_invitations).to be_empty
  end

  it 'rejects invitations when the inbox is disabled' do
    inbox.update!(web_attendance_enabled: false)
    expect { invitation_message }.to raise_error(ArgumentError, /unavailable/)
  end

  it 'does not allow enabling web attendance on other providers' do
    other_inbox = create(:inbox)
    expect(other_inbox.update(web_attendance_enabled: true)).to be(false)
    expect(other_inbox.errors[:web_attendance_enabled]).to be_present
  end

  it 'does not revoke a later pending invitation when an earlier job succeeds' do
    first = invitation
    replacement = invitation_service.create!(content: 'New invite', request_id: 'invite-request-002')
    pending = conversation.web_attendance_invitations.find_by!(message: replacement)
    first.activate!
    expect(first.reload).to be_active
    expect(pending.reload.revoked_at).to be_nil
    pending.activate!
    expect(pending.reload).to be_active
    expect(first.reload).not_to be_active
  end

  it 'does not let an out-of-order delivery reactivate an older invitation' do
    first = invitation
    replacement = invitation_service.create!(content: 'New invite', request_id: 'invite-request-002')
    newer = conversation.web_attendance_invitations.find_by!(message: replacement)
    newer.activate!
    first.activate!
    expect(newer.reload).to be_active
    expect(first.reload).not_to be_active
  end

  it 'binds the invitation to the original account, inbox and contact' do
    expect(invitation.attributes).to include('account_id' => account.id, 'inbox_id' => inbox.id, 'contact_id' => contact.id)
    invitation.activate!
    session = invitation.web_attendance_sessions.create!(token_digest: Digest::SHA256.hexdigest('identity-session'))
    conversation.update!(contact: create(:contact, account: account))
    expect(invitation.reload).not_to be_active
    expect(session.reload).not_to be_active
  end

  it 'invalidates a link when the conversation moves to another enabled Uno inbox' do
    invitation.activate!
    other_channel = create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
    other_channel.inbox.update!(web_attendance_enabled: true)
    conversation.update!(inbox: other_channel.inbox)
    expect(invitation.reload).not_to be_active
  end

  describe 'provider delivery' do
    let(:provider_url) { 'https://uno.example.com/v13.0/556600000000/messages' }

    it 'sends the configured CTA and activates only after a successful Uno response' do
      inbox.update!(web_attendance_button_text: 'Abrir atendimento')
      stub = stub_request(:post, provider_url).with do |request|
        body = JSON.parse(request.body)
        body['type'] == 'interactive' && body.dig('interactive', 'body', 'text') == 'Continue on the web' &&
          body.dig('interactive', 'action', 'buttons', 0) == {
            'type' => 'cta_url',
            'url' => { 'title' => 'Abrir atendimento', 'link' => invitation.link,
                       'webview_presentation' => 'full', 'webview_interaction' => true }
          }
      end.to_return(status: 200, body: { messages: [{ id: 'uno-accepted-001' }] }.to_json,
                    headers: { 'Content-Type' => 'application/json' })
      expect(invitation).not_to be_active
      SendReplyJob.perform_now(invitation_message.id)
      expect(stub).to have_been_requested.once
      expect(invitation_message.reload.source_id).to eq('uno-accepted-001')
      expect(invitation.reload).to be_active
      SendReplyJob.perform_now(invitation_message.id)
      expect(stub).to have_been_requested.once
    end

    it 'keeps the previous link and sessions usable when the new CTA is rejected' do
      invitation.activate!
      session = invitation.web_attendance_sessions.create!(token_digest: Digest::SHA256.hexdigest('old-session'))
      replacement = invitation_service.create!(content: 'New invite', request_id: 'invite-request-002')
      stub_request(:post, provider_url).to_return(
        status: 400, body: { error: { message: 'Unsupported CTA', code: 100 } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      SendReplyJob.perform_now(replacement.id)
      expect(replacement.reload).to be_failed
      expect(conversation.web_attendance_invitations.find_by!(message: replacement)).not_to be_active
      expect(invitation.reload).to be_active
      expect(session.reload).to be_active
    end

    it 'does not activate when Uno rejects with an error in a successful HTTP response' do
      stub_request(:post, provider_url).to_return(
        status: 200, body: { error: { message: 'Rejected', code: 100 } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      SendReplyJob.perform_now(invitation_message.id)
      expect(invitation_message.reload).to be_failed
      expect(invitation.reload).not_to be_active
    end
  end

  describe 'greeting in a single conversation inbox' do
    before do
      inbox.update!(lock_to_single_conversation: true, greeting_enabled: true,
                    greeting_message: 'Hello {{contact.name}}', web_attendance_greeting_enabled: true)
    end

    it 'sends one greeting with invitation per attendance cycle and none for administrative reopening alone' do
      create(:message, account: account, conversation: conversation, sender: contact, content: 'Hello')
      expect(conversation.web_attendance_invitations.count).to eq(1)
      first = conversation.web_attendance_invitations.first
      expect(first.message.content).to eq("Hello #{contact.name}")
      create(:message, account: account, conversation: conversation, sender: contact, content: 'Another incoming')
      expect(conversation.web_attendance_invitations.count).to eq(1)
      conversation.resolved!
      conversation.open!
      expect(conversation.web_attendance_invitations.count).to eq(1)
      expect(conversation.web_attendance_greeting_sent_at).to be_nil
      create(:message, account: account, conversation: conversation, sender: contact, content: 'New attendance')
      expect(conversation.web_attendance_invitations.count).to eq(2)
      expect(conversation.web_attendance_invitations.last.cycle).to eq(first.cycle + 1)
    end

    it 'starts a new greeting cycle when WhatsApp input reopens the resolved conversation' do
      create(:message, account: account, conversation: conversation, sender: contact)
      conversation.resolved!
      create(:message, account: account, conversation: conversation, sender: contact, content: 'Back on WhatsApp')
      expect(conversation.reload).to be_open
      expect(conversation.web_attendance_invitations.count).to eq(2)
    end

    it 'does not send greeting or invitation for incoming Web messages' do
      create(:message, account: account, conversation: conversation, sender: contact, delivery_destination: 'web')
      expect(conversation.web_attendance_invitations).to be_empty
    end
  end
end
