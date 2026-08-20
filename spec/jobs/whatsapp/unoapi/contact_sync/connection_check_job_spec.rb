require 'rails_helper'

describe Whatsapp::Unoapi::ContactSync::ConnectionCheckJob do
  let(:channel) do
    create(
      :channel_whatsapp,
      provider: 'unoapi',
      contact_sync_enabled: true,
      contact_sync_status: 'waiting_connection',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:client) { instance_double(Whatsapp::Unoapi::ContactSync::Client, session_online?: true) }

  before do
    allow(Whatsapp::Unoapi::ContactSync::Client).to receive(:new).with(channel).and_return(client)
  end

  it 'waits three minutes before the first synchronization' do
    freeze_time do
      expect do
        described_class.perform_now(channel.id)
      end.to have_enqueued_job(Whatsapp::Unoapi::ContactSync::PageJob)
        .with(channel.id, '0')
        .at(3.minutes.from_now)

      expect(channel.reload).to have_attributes(
        contact_sync_status: 'scheduled',
        contact_sync_cursor: '0',
        contact_sync_next_run_at: be_within(1.second).of(3.minutes.from_now)
      )
    end
  end

  it 'starts subsequent synchronizations immediately' do
    channel.update_columns(contact_sync_completed_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations

    expect do
      described_class.perform_now(channel.id)
    end.to have_enqueued_job(Whatsapp::Unoapi::ContactSync::PageJob).with(channel.id, '0')
  end
end
