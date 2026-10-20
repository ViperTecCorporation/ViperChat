require 'rails_helper'

RSpec.describe Whatsapp::RequestSmbAppDataJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }

  it 'does nothing for a removed channel' do
    expect(Whatsapp::SmbAppDataService).not_to receive(:new)
    described_class.perform_now(-1)
  end

  it 'enqueues only a bounded preparation retry when the subscription fails, without resetting the journal' do
    service = instance_double(Whatsapp::SmbAppDataService)
    allow(Whatsapp::SmbAppDataService).to receive(:new).with(channel: channel).and_return(service)
    allow(service).to receive(:perform).and_raise(Whatsapp::SmbAppDataService::PreparationError, 'webhook_setup_failed')
    expect { described_class.perform_now(channel.id) }.to have_enqueued_job(described_class).with(channel.id)
                                                                                            .at(a_value_between(5.minutes.from_now,
                                                                                                                6.minutes.from_now))
    expect(WhatsappSmbSyncRequest.count).to eq(0)
  end
end
