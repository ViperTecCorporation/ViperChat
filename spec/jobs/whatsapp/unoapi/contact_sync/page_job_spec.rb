require 'rails_helper'

describe Whatsapp::Unoapi::ContactSync::PageJob do
  let(:channel) do
    create(
      :channel_whatsapp,
      provider: 'unoapi',
      contact_sync_enabled: true,
      contact_sync_status: 'scheduled',
      contact_sync_cursor: '0',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:client) { instance_double(Whatsapp::Unoapi::ContactSync::Client, session_online?: true) }
  let(:importer) { instance_double(Whatsapp::Unoapi::ContactSync::ContactImporter, perform: :processed) }
  let(:job) { described_class.new }
  let(:page) do
    {
      'contacts' => [
        { 'user_id' => '1@lid', 'last_updated_ms' => 10 },
        { 'user_id' => '2@lid', 'last_updated_ms' => 20 }
      ],
      'next_cursor' => '42',
      'has_more' => true,
      'total_count' => 3
    }
  end

  before do
    allow(job).to receive(:with_lock).and_yield
    allow(Whatsapp::Unoapi::ContactSync::Client).to receive(:new).with(channel).and_return(client)
    allow(client).to receive(:contacts).with(cursor: '0').and_return(page)
    allow(Whatsapp::Unoapi::ContactSync::ContactImporter).to receive(:build_for_page).and_return([importer, importer])
  end

  it 'processes one page, advances the cursor, and enqueues only the next page' do
    expect do
      job.perform(channel.id, '0')
    end.to have_enqueued_job(described_class).with(channel.id, '42')

    expect(channel.reload).to have_attributes(
      contact_sync_status: 'scheduled',
      contact_sync_cursor: '42',
      contact_sync_processed_count: 2,
      contact_sync_failed_count: 0,
      contact_sync_total_count: 3
    )
  end

  it 'ignores a duplicate job for a cursor that was already completed' do
    channel.update_columns(contact_sync_cursor: '42') # rubocop:disable Rails/SkipsModelValidations

    job.perform(channel.id, '0')

    expect(client).not_to have_received(:contacts)
  end

  it 'pauses the synchronization when the contact directory requires Zapo' do
    allow(client).to receive(:contacts).and_raise(
      Whatsapp::Unoapi::ContactSync::Client::ProviderMismatchError,
      'contact_directory_requires_zapo_provider'
    )

    job.perform(channel.id, '0')

    expect(channel.reload).to have_attributes(
      contact_sync_status: 'paused',
      contact_sync_error: 'contact_directory_requires_zapo_provider',
      contact_sync_next_run_at: nil
    )
  end
end
