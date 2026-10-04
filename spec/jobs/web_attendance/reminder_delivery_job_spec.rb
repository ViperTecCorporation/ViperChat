require 'rails_helper'

RSpec.describe WebAttendance::ReminderDeliveryJob do
  include_context 'with Uno web attendance'
  include ActiveSupport::Testing::TimeHelpers

  let(:delivery) { instance_double(Whatsapp::SendOnWhatsappService) }
  let(:reminder) { conversation.messages.where.not(web_absence_request_key: nil).sole }

  before do
    invitation.activate!
    create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing, delivery_destination: 'web')
    travel 16.seconds
    WebAttendance::AbsenceReminderService.new(conversation).perform!(conversation.web_attendance_cycle, conversation.web_absence_epoch)
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(delivery)
    allow(HTTParty).to receive(:post).and_raise('Real sends are forbidden in these tests')
  end

  it 'attempts once even when the provider raises and the job is retried' do
    expect(described_class.new.send(:deliverable?, reminder)).to be(true)
    expect(delivery).to receive(:perform).once.and_raise('Ambiguous provider timeout')
    expect { described_class.perform_now(reminder.id) }.to raise_error('Ambiguous provider timeout')
    expect(reminder.reload.web_reminder_attempted_at).to be_present
    expect(reminder).to be_failed
    described_class.perform_now(reminder.id)
    expect(reminder.reload).to be_failed
    expect(reminder.external_error).to include('uncertain')
  end

  it 'does not deliver after the visitor returns' do
    session = invitation.web_attendance_sessions.create!(token_digest: SecureRandom.hex(32))
    conversation.with_lock { WebAttendance::PresenceService.new(conversation).heartbeat!(session, true) }
    expect(delivery).not_to receive(:perform)
    described_class.perform_now(reminder.id)
    expect(reminder.reload.external_error).to include('cancelled')
  end

  it 'rechecks revocation before external delivery' do
    invitation.update!(revoked_at: Time.current)
    expect(delivery).not_to receive(:perform)
    described_class.perform_now(reminder.id)
  end

  it 'rechecks the reply window before external delivery' do
    window = instance_double(Conversations::MessageWindowService, can_reply?: false)
    allow(Conversations::MessageWindowService).to receive(:new).and_return(window)
    expect(delivery).not_to receive(:perform)
    described_class.perform_now(reminder.id)
  end

  it 'cancels when the original message is read between creation and delivery' do
    original = conversation.messages.find(reminder.content_attributes['web_absence_message_id'])
    original.update!(status: :read)
    expect(delivery).not_to receive(:perform)
    described_class.perform_now(reminder.id)
    expect(reminder.reload).to be_failed
  end

  it 'marks provider-confirmed delivery as sent and never delivers a duplicate job' do
    expect(delivery).to receive(:perform).once do
      reminder.update!(source_id: 'test-provider-id')
    end
    described_class.perform_now(reminder.id)
    expect(reminder.reload).to be_sent
    described_class.perform_now(reminder.id)
  end

  it 'routes generic send jobs through the same at-most-once delivery guard' do
    expect(Whatsapp::SendOnWhatsappService).not_to receive(:new)
    expect(described_class).to receive(:perform_later).with(reminder.id)
    SendReplyJob.perform_now(reminder.id)
  end
end
