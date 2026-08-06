require 'rails_helper'

describe Whatsapp::Unoapi::ContactSync::ExportJob do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'unoapi',
      contact_sync_enabled: true,
      contact_export_enabled: true,
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5566999069708') }
  let(:other_contact) { create(:contact, account: account, phone_number: '+5566999554300') }
  let(:client) { instance_double(Whatsapp::Unoapi::ContactSync::Client) }
  let(:exporter) { instance_double(Whatsapp::Unoapi::ContactSync::ContactExporter, perform: :processed) }
  let(:job) { described_class.new }

  before do
    create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '5566999069708')
    other_channel = create(
      :channel_whatsapp,
      account: account,
      provider: 'unoapi',
      sync_templates: false,
      validate_provider_config: false
    )
    create(:contact_inbox, inbox: other_channel.inbox, contact: other_contact, source_id: '5566999554300')
    allow(job).to receive(:with_lock).and_yield
    allow(Whatsapp::Unoapi::ContactSync::Client).to receive(:new).with(channel).and_return(client)
    allow(Whatsapp::Unoapi::ContactSync::ContactExporter).to receive(:new).and_return(exporter)
  end

  it 'exports only contacts linked to the channel inbox' do
    job.perform(channel.id)

    expect(Whatsapp::Unoapi::ContactSync::ContactExporter).to have_received(:new).once.with(
      channel: channel,
      contact: contact,
      client: client
    )
    expect(exporter).to have_received(:perform).once
  end

  it 'does nothing when outbound synchronization is disabled' do
    channel.update_columns(contact_export_enabled: false) # rubocop:disable Rails/SkipsModelValidations

    job.perform(channel.id)

    expect(Whatsapp::Unoapi::ContactSync::ContactExporter).not_to have_received(:new)
  end

  it 'continues the batch when one contact verification times out' do
    next_contact = create(:contact, account: account, phone_number: '+5566999223344')
    create(:contact_inbox, inbox: channel.inbox, contact: next_contact, source_id: '5566999223344')
    timed_out_exporter = instance_double(Whatsapp::Unoapi::ContactSync::ContactExporter)
    successful_exporter = instance_double(Whatsapp::Unoapi::ContactSync::ContactExporter, perform: :processed)
    allow(timed_out_exporter).to receive(:perform)
      .and_raise(Whatsapp::Unoapi::ContactSync::Client::TransientError, 'UnoAPI HTTP 500: query timeout')
    allow(Whatsapp::Unoapi::ContactSync::ContactExporter).to receive(:new)
      .and_return(timed_out_exporter, successful_exporter)

    expect { job.perform(channel.id) }.not_to raise_error
    expect(timed_out_exporter).to have_received(:perform)
    expect(successful_exporter).to have_received(:perform)
  end
end
