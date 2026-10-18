require 'rails_helper'

RSpec.describe WebAttendance::InvitationService do
  include_context 'with Uno web attendance'

  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              provider_config: { 'url' => 'https://cloud.example.com', 'api_key' => 'test_key',
                                                 'phone_number_id' => '556600000000', 'business_account_id' => '556600000000' })
  end
  let(:provider_url) { "https://cloud.example.com/v26.0/#{channel.provider_config['phone_number_id']}/messages" }

  before do
    create(:message, account: account, conversation: conversation, sender: contact, created_at: 1.hour.ago)
  end

  it 'enables Cloud with a compatible default CTA label' do
    expect(inbox).to be_web_attendance_available
    expect(inbox.web_attendance_button_text).to eq('Abrir atendimento')
    expect(inbox.web_attendance_button_limit).to eq(20)
  end

  it 'sends the Cloud CTA payload without Uno WebView fields and activates only after acceptance' do
    original = invitation_message
    request = stub_request(:post, provider_url).with do |outgoing|
      body = JSON.parse(outgoing.body)
      body == { 'messaging_product' => 'whatsapp', 'to' => conversation.contact_inbox.source_id, 'type' => 'interactive',
                'interactive' => { 'type' => 'cta_url', 'body' => { 'text' => original.content },
                                   'action' => { 'name' => 'cta_url', 'parameters' => {
                                     'display_text' => 'Abrir atendimento', 'url' => invitation.link
                                   } } } }
    end.to_return(status: 200, body: { messages: [{ id: 'cloud-invite-001' }] }.to_json,
                  headers: { 'Content-Type' => 'application/json' })
    SendReplyJob.perform_now(original.id)
    expect(original.reload.source_id).to eq('cloud-invite-001')
    expect(invitation.reload).to be_active
    SendReplyJob.perform_now(original.id)
    expect(request).to have_been_requested.once
  end

  it 'preserves the previous invitation and session when Cloud rejects the replacement' do
    invitation.activate!
    session = invitation.web_attendance_sessions.create!(token_digest: Digest::SHA256.hexdigest('cloud-session'))
    replacement = invitation_service.create!(content: 'New link', request_id: 'cloud-replacement')
    stub_request(:post, provider_url).to_return(
      status: 400, body: { error: { message: 'Rejected' } }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    SendReplyJob.perform_now(replacement.id)
    expect(replacement.reload).to be_failed
    expect(invitation.reload).to be_active
    expect(session.reload).to be_active
  end

  it 'refuses creation outside the window and Web activity does not renew it' do
    conversation.messages.incoming.where(delivery_destination: 'channel').find_each { |message| message.update!(created_at: 25.hours.ago) }
    create(:message, account: account, conversation: conversation, sender: contact, delivery_destination: 'web')
    expect(conversation.reload.can_reply?).to be(false)
    expect { invitation_message }.to raise_error(ArgumentError, /approved template/)
    expect(conversation.web_attendance_invitations.count).to eq(0)
  end

  it 'does not fall back to a template or send a delayed invitation after the window expires' do
    original = invitation_message
    travel 25.hours do
      expect(channel).not_to receive(:send_template)
      expect(channel).not_to receive(:send_message)
      SendReplyJob.perform_now(original.id)
      expect(original.reload).to be_failed
      expect(invitation.reload).not_to be_active
    end
  end

  it 'keeps public Web replies internal even when the WhatsApp window is closed' do
    conversation.messages.incoming.where(delivery_destination: 'channel').find_each { |message| message.update!(created_at: 25.hours.ago) }
    message = create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing,
                               delivery_destination: 'web', content: 'Web reply')
    expect(channel).not_to receive(:send_message)
    SendReplyJob.perform_now(message.id)
    expect(message.reload.source_id).to be_nil
    expect(message.sender).to eq(user)
  end

  it 'retains greeting invitations once per cycle in the open window' do
    inbox.update!(greeting_enabled: true, greeting_message: 'Welcome', web_attendance_greeting_enabled: true)
    conversation.reload
    expect(ChatwootExceptionTracker).not_to receive(:new)
    MessageTemplates::Template::Greeting.new(conversation: conversation).perform
    MessageTemplates::Template::Greeting.new(conversation: conversation).perform
    expect(conversation.web_attendance_invitations.count).to eq(1)
    expect(conversation.web_attendance_invitations.first.message.content).to eq('Welcome')
  end

  it 'rejects invitation bodies above the Cloud limit before creating a link' do
    expect { invitation_service.create!(content: 'a' * 1025, request_id: 'cloud-long-invite') }.to raise_error(ArgumentError, /too long/)
    expect(conversation.web_attendance_invitations.count).to eq(0)
  end

  it 'rejects custom CTA labels above the Cloud limit' do
    expect(inbox.update(web_attendance_button_text: 'a' * 21)).to be(false)
    expect(inbox.errors[:web_attendance_button_text]).to be_present
  end

  it 'rejects oversized greeting CTA configuration before receiving messages' do
    expect(inbox.update(greeting_message: 'a' * 1025, web_attendance_greeting_enabled: true)).to be(false)
    expect(inbox.errors[:greeting_message]).to be_present
  end

  it 'sends an absence reminder once using the same Cloud invitation URL' do
    invitation.activate!
    create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing,
                     delivery_destination: 'web', content: 'Only on Web')
    travel 16.seconds
    conversation.reload
    service = WebAttendance::AbsenceReminderService.new(conversation)
    2.times { service.perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch) }
    reminder = conversation.messages.where.not(web_absence_request_key: nil).sole
    request = stub_request(:post, provider_url).with do |outgoing|
      body = JSON.parse(outgoing.body)
      body.dig('interactive', 'action', 'parameters', 'url') == invitation.link &&
        body.dig('interactive', 'body', 'text') == WebAttendance::AbsenceReminderService::CONTENT
    end.to_return(status: 200, body: { messages: [{ id: 'cloud-reminder-001' }] }.to_json,
                  headers: { 'Content-Type' => 'application/json' })
    2.times { WebAttendance::ReminderDeliveryJob.perform_now(reminder.id) }
    expect(reminder.reload).to be_sent
    expect(request).to have_been_requested.once
  end

  it 'suppresses absence reminders when only Web activity is inside the window' do
    invitation.activate!
    travel 25.hours
    create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing, delivery_destination: 'web')
    travel 16.seconds
    conversation.reload
    WebAttendance::AbsenceReminderService.new(conversation).perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch)
    expect(conversation.messages.where.not(web_absence_request_key: nil)).to be_empty
  end
end
