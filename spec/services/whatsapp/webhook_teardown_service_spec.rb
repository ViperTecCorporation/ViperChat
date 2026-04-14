require 'rails_helper'

RSpec.describe Whatsapp::WebhookTeardownService do
  describe '#perform' do
    let(:channel) { create(:channel_whatsapp, validate_provider_config: false, sync_templates: false) }
    let(:service) { described_class.new(channel) }

    context 'when channel is whatsapp_cloud with embedded_signup' do
      before do
        # Stub webhook setup to prevent HTTP calls during channel update
        allow(channel).to receive(:setup_webhooks).and_return(true)

        channel.update!(
          provider: 'whatsapp_cloud',
          provider_config: {
            'source' => 'embedded_signup',
            'business_account_id' => 'test_waba_id',
            'api_key' => 'test_api_key'
          }
        )
      end

      it 'does not unsubscribe the WABA webhook' do
        expect(Whatsapp::FacebookApiClient).not_to receive(:new)

        service.perform
      end

      it 'does not block channel deletion' do
        expect { service.perform }.not_to raise_error
      end
    end

    context 'when channel is not whatsapp_cloud' do
      before do
        channel.update!(provider: 'default')
      end

      it 'does not attempt to unsubscribe webhook' do
        expect(Whatsapp::FacebookApiClient).not_to receive(:new)

        service.perform
      end
    end

    context 'when channel is whatsapp_cloud but not embedded_signup' do
      before do
        channel.update!(
          provider: 'whatsapp_cloud',
          provider_config: { 'source' => 'manual' }
        )
      end

      it 'does not attempt to unsubscribe webhook' do
        expect(Whatsapp::FacebookApiClient).not_to receive(:new)

        service.perform
      end
    end

    context 'when required config is missing' do
      before do
        channel.update!(
          provider: 'whatsapp_cloud',
          provider_config: { 'source' => 'embedded_signup' }
        )
      end

      it 'does not attempt to unsubscribe webhook' do
        expect(Whatsapp::FacebookApiClient).not_to receive(:new)

        service.perform
      end
    end
  end
end
