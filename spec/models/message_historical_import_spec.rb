require 'rails_helper'

RSpec.describe Message, '#historical_import' do
  let(:conversation) { create(:conversation, historical_import: true, status: :resolved).reload }
  let(:message) do
    build(:message, account: conversation.account, conversation: conversation, sender: conversation.contact,
                    historical_import: true, created_at: 3.days.ago.change(usec: 0))
  end

  it 'persists an incoming message without live delivery, activity, notification or automation callbacks' do
    %i[reopen_conversation mark_pending_conversation_as_open_for_human_response set_conversation_activity
       mark_replying_agent_notifications_read dispatch_create_events send_reply execute_message_template_hooks
       update_contact_activity enqueue_link_preview].each do |callback|
      expect(message).not_to receive(callback)
    end
    expect(SendReplyJob).not_to receive(:perform_later)

    message.save!

    expect(message.id).to be_present
    expect(message.reload.content).to eq('Incoming Message')
  end

  it 'does not change the current conversation or contact activity and waiting state' do
    original_activity = conversation.last_activity_at
    original_contact_activity = conversation.contact.last_activity_at
    original_last_seen = conversation.agent_last_seen_at
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    message.save!

    expect(conversation.reload).to be_resolved
    expect(conversation.waiting_since).to be_nil
    expect(conversation.last_activity_at).to eq(original_activity)
    expect(conversation.agent_last_seen_at).to eq(original_last_seen)
    expect(conversation.contact.reload.last_activity_at).to eq(original_contact_activity)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with('message.created', anything, anything)
  end

  it 'does not schedule a web absence reminder for a historical outgoing message' do
    message.message_type = :outgoing
    expect(WebAttendance::AbsenceReminderService).not_to receive(:new)
    expect(message).not_to receive(:send_reply)

    message.save!
    message.delivery_destination = 'web'
    message.sender = create(:user, account: conversation.account)
    message.schedule_web_absence_reminder
  end

  it 'keeps content and account validations enabled' do
    message.content = 'a' * 150_001
    message.account = nil

    expect(message).not_to be_valid
    expect(message.errors[:content]).to be_present
    expect(message.errors[:account_id]).to be_present
  end

  it 'does not apply the live flood threshold to a valid historical batch' do
    allow(Limits).to receive(:conversation_message_per_minute_limit).and_return(1)
    create(:message, account: conversation.account, conversation: conversation, historical_import: true)
    message.created_at = Time.current
    expect(message).to be_valid
    message.historical_import = nil
    expect(message).not_to be_valid
  end

  it 'dispatches normal updates after reload despite the original insertion context' do
    message.save!
    message.reload
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    message.update!(status: :read)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
      'message.updated', kind_of(Time), hash_including(message: message, previous_changes: anything)
    )
    expect(described_class.find(message.id).historical_import).to be_nil
  end

  it 'keeps the normal creation callbacks for messages without the context' do
    message.historical_import = nil
    expect(message).to receive(:reopen_conversation).and_call_original
    expect(message).to receive(:dispatch_create_events).and_call_original
    expect(message).to receive(:send_reply).and_call_original

    message.save!

    expect(conversation.reload).to be_open
  end
end
