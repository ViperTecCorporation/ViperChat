require 'rails_helper'

RSpec.describe WebAttendance::AbsenceReminderService do
  include_context 'with Uno web attendance'
  include ActiveSupport::Testing::TimeHelpers

  let(:service) { described_class.new(conversation) }
  let(:session) { invitation.web_attendance_sessions.create!(token_digest: SecureRandom.hex(32)) }
  let(:reply) do
    create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing,
                     delivery_destination: 'web', content: 'Private Web payload, never WhatsApp')
  end
  let(:reminders) { conversation.messages.where.not(web_absence_request_key: nil) }

  before do
    invitation.activate!
    allow(HTTParty).to receive(:post).and_raise('Real sends are forbidden in these tests')
  end

  it 'isolates presence and scheduling updates from automation events' do
    allow(EventDispatcherJob).to receive(:perform_later)
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, true) }
    expect(EventDispatcherJob).not_to have_received(:perform_later).with(
      'conversation.updated', anything, hash_not_including(web_attendance: true)
    )
    expect(Current.web_attendance_conversation_id).to be_nil
  end

  it 'schedules only public agent Web replies' do
    expect(WebAttendance::AbsenceReminderJob).to receive(:set).with(wait: 15.seconds).and_call_original
    reply
    expect(conversation.reload.web_reminder_pending_message_id).to eq(reply.id)
    expect(WebAttendance::AbsenceReminderJob).not_to receive(:set)
    create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing, private: true,
                     delivery_destination: 'web')
    create(:message, account: account, conversation: conversation, sender: contact, delivery_destination: 'web')
  end

  it 'waits 15 seconds and creates one CTA with the existing invitation, never the Web payload' do
    reply
    cycle = conversation.reload.web_attendance_cycle
    epoch = conversation.web_absence_epoch
    service.perform!(cycle, epoch)
    expect(reminders.count).to eq(0)
    travel 16.seconds
    expect { 2.times { service.perform!(cycle, epoch) } }.not_to change(WebAttendanceInvitation, :count)
    reminder = reminders.sole
    expect(reminder.content).to eq(described_class::CONTENT)
    expect(reminder.delivery_destination).to eq('channel')
    expect(reminder.content_attributes['web_attendance_invitation_id']).to eq(invitation.id)
    expect(reminder.content).not_to include(reply.content)
    create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing, delivery_destination: 'web')
    travel 16.seconds
    service.perform!(cycle, epoch)
    expect(reminders.count).to eq(1)
  end

  it 'treats stale heartbeats as disconnected and waits 15 seconds after freshness expires' do
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, true) }
    reply
    cycle = conversation.reload.web_attendance_cycle
    epoch = conversation.web_absence_epoch
    travel 16.seconds
    service.perform!(cycle, epoch)
    expect(reminders).to be_empty
    travel 10.seconds
    service.perform!(cycle, epoch)
    expect(reminders.count).to eq(1)
  end

  it 'does not postpone or duplicate the first pending check when another reply arrives' do
    reply
    travel 10.seconds
    expect(WebAttendance::AbsenceReminderJob).not_to receive(:set)
    create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing, delivery_destination: 'web')
    expect(conversation.reload.web_reminder_pending_message_id).to eq(reply.id)
    travel 6.seconds
    service.perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch)
    expect(reminders.count).to eq(1)
  end

  it 'checks once while online then clears pending work without recurring jobs or a reminder on later departure' do
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, true) }
    reply
    2.times do
      travel 8.seconds
      conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, true) }
    end
    expect(WebAttendance::AbsenceReminderJob).not_to receive(:set)
    service.perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch)
    expect(conversation.reload.web_reminder_pending_message_id).to be_nil
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, false) }
    travel 16.seconds
    service.perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch)
    expect(reminders).to be_empty
  end

  it 'clears an already-read pending message without sending or polling jobs' do
    reply.update!(status: :read)
    travel 16.seconds
    expect(WebAttendance::AbsenceReminderJob).not_to receive(:set)
    service.perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch)
    expect(reminders).to be_empty
    expect(conversation.reload.web_reminder_pending_message_id).to be_nil
  end

  it 'keeps a visible tab online when another tab sharing the same cookie is hidden' do
    visible_tab = SecureRandom.uuid
    hidden_tab = SecureRandom.uuid
    conversation.with_lock do
      presence = WebAttendance::PresenceService.new(conversation)
      presence.heartbeat!(session, true, presence_id: visible_tab)
      presence.heartbeat!(session, false, presence_id: hidden_tab)
    end
    expect(conversation.reload.web_presence_online).to be(true)
    expect(session.reload.presence_entries.keys).to contain_exactly(visible_tab, hidden_tab)
    reply
    travel 11.seconds
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, false, presence_id: hidden_tab) }
    expect(conversation.reload.web_presence_online).to be(false)
    expect(session.reload.presence_entries.keys).to eq([hidden_tab])
  end

  it 'suppresses a reminder while any other session has a fresh visible heartbeat' do
    other = invitation.web_attendance_sessions.create!(token_digest: SecureRandom.hex(32))
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, true) }
    reply
    epoch = conversation.reload.web_absence_epoch
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, false) }
    travel 16.seconds
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(other, true) }
    service.perform!(conversation.web_attendance_cycle, epoch)
    expect(reminders).to be_empty
    expect(conversation.reload.web_reminder_pending_message_id).to be_nil
  end

  it 'does not reset the epoch on consecutive online heartbeats; return requires a new message and absence' do
    reply
    travel 16.seconds
    service.perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch)
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, true) }
    epoch = conversation.reload.web_absence_epoch
    3.times { conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, true) } }
    expect(conversation.reload.web_absence_epoch).to eq(epoch)
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, false) }
    travel 16.seconds
    service.perform!(conversation.web_attendance_cycle, epoch)
    expect(reminders.count).to eq(1)
    create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing, delivery_destination: 'web')
    travel 16.seconds
    service.perform!(conversation.web_attendance_cycle, epoch)
    expect(reminders.count).to eq(2)
  end

  it 'cancels for revocation, resolution, disabled attendance and obsolete cycles' do
    reply
    travel 16.seconds
    cycle = conversation.reload.web_attendance_cycle
    epoch = conversation.web_absence_epoch
    service.perform!(cycle - 1, epoch)
    expect(reminders).to be_empty
    invitation.update!(revoked_at: Time.current)
    service.perform!(cycle, epoch)
    expect(reminders).to be_empty
    invitation.update!(revoked_at: nil)
    inbox.update!(web_attendance_enabled: false)
    service.perform!(cycle, epoch)
    expect(reminders).to be_empty
    inbox.update!(web_attendance_enabled: true)
    conversation.reload.resolved!
    service.perform!(cycle, epoch)
    expect(reminders).to be_empty
  end

  it 'does not send a free-form CTA outside the configured reply window' do
    reply
    travel 16.seconds
    window = instance_double(Conversations::MessageWindowService, can_reply?: false)
    allow(Conversations::MessageWindowService).to receive(:new).and_return(window)
    service.perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch)
    expect(reminders).to be_empty
  end

  it 'enforces the episode request key in the database' do
    reply
    travel 16.seconds
    service.perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch)
    attrs = reminders.sole.attributes.except('id', 'created_at', 'updated_at')
    expect { Message.create!(attrs) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
