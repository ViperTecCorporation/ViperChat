require 'rails_helper'

RSpec.describe Whatsapp::ImportHistoryJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let!(:event) do
    WhatsappManagementEvent.create!(account: channel.account, channel: channel, inbox: channel.inbox, field: 'history',
                                     digest: 'a' * 64, state: 'pending_import', expires_at: 7.days.from_now)
  end

  it 'enqueues an immediate import after receipt creation' do
    expect(described_class).to have_been_enqueued.with(event.id)
  end

  it 'retries pending receipts on a sweep but never completed or expired receipts' do
    importer = instance_double(Whatsapp::HistoryImportService, perform: nil)
    expect(Whatsapp::HistoryImportService).to receive(:new).with(event: event).and_return(importer)
    described_class.perform_now
    event.update!(state: 'processed')
    expect(Whatsapp::HistoryImportService).not_to receive(:new)
    described_class.perform_now
    event.update!(state: 'pending_import', expires_at: 1.minute.ago)
    described_class.perform_now
  end

  it 'does not let one failed receipt block another and logs only technical identifiers' do
    other = WhatsappManagementEvent.create!(account: channel.account, channel: channel, inbox: channel.inbox, field: 'history',
                                             digest: 'b' * 64, state: 'pending_import', expires_at: 7.days.from_now)
    first = instance_double(Whatsapp::HistoryImportService)
    second = instance_double(Whatsapp::HistoryImportService)
    allow(Whatsapp::HistoryImportService).to receive(:new).with(event: event).and_return(first)
    allow(Whatsapp::HistoryImportService).to receive(:new).with(event: other).and_return(second)
    allow(first).to receive(:perform).and_raise(StandardError, 'private-message-and-token')
    expect(second).to receive(:perform)
    expect(Rails.logger).not_to receive(:warn).with(include('private-message-and-token'))
    described_class.perform_now
  end
end
