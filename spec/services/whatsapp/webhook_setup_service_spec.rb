require 'rails_helper'

describe Whatsapp::WebhookSetupService do
  let(:channel) do
    create(:channel_whatsapp,
           phone_number: '+1234567890',
           provider_config: {
             'phone_number_id' => '123456789',
             'webhook_verify_token' => 'test_verify_token',
             'source' => 'embedded_signup'
           },
           provider: 'whatsapp_cloud',
           sync_templates: false,
           validate_provider_config: false)
  end
  let(:waba_id) { 'test_waba_id' }
  let(:access_token) { 'test_access_token' }
  let(:service) { described_class.new(channel, waba_id, access_token) }
  let(:api_client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:health_service) { instance_double(Whatsapp::HealthService) }

  before do
    # Stub webhook teardown to prevent HTTP calls during cleanup
    stub_request(:delete, /graph.facebook.com/).to_return(status: 200, body: '{}', headers: {})

    # Clean up any existing channels to avoid phone number conflicts
    Channel::Whatsapp.destroy_all
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(api_client)
    allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)

    # Default stubs for phone_number_verified? and health service
    allow(api_client).to receive(:phone_number_verified?).and_return(false)
    allow(health_service).to receive(:fetch_health_status).and_return({
                                                                        platform_type: 'APPLICABLE',
                                                                        throughput: { level: 'APPLICABLE' }
                                                                      })
  end

  describe '#register_callback webhook field union' do
    let(:sibling) do
      create(:channel_whatsapp,
             account: channel.account,
             phone_number: '+1234567891',
             provider: 'whatsapp_cloud',
             provider_config: { 'business_account_id' => waba_id, 'phone_number_id' => 'sibling_phone' },
             sync_templates: false,
             validate_provider_config: false).tap do |sibling_channel|
        # The factory overwrites business_account_id during creation.
        sibling_channel.update!(provider_config: sibling_channel.provider_config.merge('business_account_id' => waba_id))
      end
    end

    before do
      channel.update!(provider_config: channel.provider_config.merge('business_account_id' => waba_id))
      allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
    end

    it 'unions whitelisted optional fields from this inbox with the mandatory defaults' do
      channel.update!(provider_config: channel.provider_config.merge('webhook_fields' => %w[history message_echoes messages]))

      service.register_callback

      expect(api_client).to have_received(:subscribe_phone_number_webhook)
        .with(waba_id, '123456789', anything, 'test_verify_token',
              subscribed_fields: match_array(%w[messages smb_message_echoes history message_echoes]))
    end

    it 'unions and deduplicates optional fields from a sibling on the same WABA' do
      channel.update!(provider_config: channel.provider_config.merge('webhook_fields' => %w[history]))
      sibling.update!(provider_config: sibling.provider_config.merge('webhook_fields' => %w[history group_lifecycle_update]))

      service.register_callback

      expect(api_client).to have_received(:subscribe_phone_number_webhook)
        .with(waba_id, '123456789', anything, 'test_verify_token',
              subscribed_fields: match_array(%w[messages smb_message_echoes history group_lifecycle_update]))
    end

    it 'rejects unknown fields from both this inbox and a sibling while retaining known fields' do
      channel.update!(provider_config: channel.provider_config.merge('webhook_fields' => %w[unknown_own history]))
      sibling.update!(provider_config: sibling.provider_config.merge('webhook_fields' => %w[unknown_sibling account_update]))

      service.register_callback

      expect(api_client).to have_received(:subscribe_phone_number_webhook)
        .with(waba_id, '123456789', anything, 'test_verify_token',
              subscribed_fields: match_array(%w[messages smb_message_echoes history account_update]))
    end

    it 'preserves calls enabled on this inbox alongside optional fields' do
      channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => true, 'webhook_fields' => %w[history calls]))

      service.register_callback

      expect(api_client).to have_received(:subscribe_phone_number_webhook)
        .with(waba_id, '123456789', anything, 'test_verify_token',
              subscribed_fields: match_array(%w[messages smb_message_echoes history calls]))
    end

    it 'preserves calls enabled on a same-WABA sibling when this inbox has calling disabled' do
      channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => false, 'webhook_fields' => %w[history]))
      sibling.update!(provider_config: sibling.provider_config.merge('calling_enabled' => true, 'webhook_fields' => %w[account_update calls]))

      service.register_callback

      expect(api_client).to have_received(:subscribe_phone_number_webhook)
        .with(waba_id, '123456789', anything, 'test_verify_token',
              subscribed_fields: match_array(%w[messages smb_message_echoes history account_update calls]))
    end

    it 'does not enable calls merely because the optional field is listed on this inbox or its sibling' do
      channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => false, 'webhook_fields' => %w[history calls]))
      sibling.update!(provider_config: sibling.provider_config.merge('calling_enabled' => false, 'webhook_fields' => %w[calls]))

      service.register_callback

      expect(api_client).to have_received(:subscribe_phone_number_webhook)
        .with(waba_id, '123456789', anything, 'test_verify_token',
              subscribed_fields: match_array(%w[messages smb_message_echoes history]))
    end

    it 'does not inherit optional fields or calls from a different WABA' do
      sibling.update!(provider_config: sibling.provider_config.merge(
        'business_account_id' => 'other_waba', 'calling_enabled' => true, 'webhook_fields' => %w[history calls]
      ))

      service.register_callback

      expect(api_client).to have_received(:subscribe_phone_number_webhook)
        .with(waba_id, '123456789', anything, 'test_verify_token',
              subscribed_fields: match_array(%w[messages smb_message_echoes]))
    end

    it 'does not inherit optional fields or calls from a non-Meta sibling' do
      sibling.update!(provider: 'unoapi',
                      provider_config: sibling.provider_config.merge('calling_enabled' => true, 'webhook_fields' => %w[history calls]))

      service.register_callback

      expect(api_client).to have_received(:subscribe_phone_number_webhook)
        .with(waba_id, '123456789', anything, 'test_verify_token',
              subscribed_fields: match_array(%w[messages smb_message_echoes]))
    end
  end

  describe '#perform' do
    context 'when phone number is NOT verified (should register)' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(false)
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number).with('123456789', 223_456)
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'registers the phone number and sets up webhook' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'test_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service.perform
        end
      end
    end

    context 'when phone number IS verified AND fully provisioned (should NOT register)' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(true)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
      end

      it 'does NOT register phone, but sets up webhook' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).not_to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'test_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service.perform
        end
      end
    end

    context 'when phone number IS verified BUT needs registration (pending provisioning)' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(true)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'NOT_APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number).with('123456789', 223_456)
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'registers the phone number due to pending provisioning state' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'test_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service.perform
        end
      end
    end

    context 'when phone number needs registration due to throughput level' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(true)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'NOT_APPLICABLE' }
                                                                          })
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number).with('123456789', 223_456)
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'registers the phone number due to throughput not applicable' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'test_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service.perform
        end
      end
    end

    context 'when phone_number_verified? raises error' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_raise('API down')
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'tries to register phone (due to verification error) and proceeds with webhook setup' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
          expect { service.perform }.not_to raise_error
        end
      end
    end

    context 'when health service raises error' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(true)
        allow(health_service).to receive(:fetch_health_status).and_raise('Health API down')
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
      end

      it 'does not register phone (conservative approach) and proceeds with webhook setup' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).not_to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
          expect { service.perform }.not_to raise_error
        end
      end
    end

    context 'when phone registration fails (not blocking)' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(false)
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number).and_raise('Registration failed')
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'continues with webhook setup even if registration fails' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
          expect { service.perform }.not_to raise_error
        end
      end
    end

    context 'when webhook setup fails (should raise)' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(false)
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_raise('Webhook failed')
      end

      it 'raises an error' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
          expect { service.perform }.to raise_error(/Webhook setup failed/)
        end
      end
    end

    context 'when required parameters are missing' do
      it 'raises error when channel is nil' do
        service_invalid = described_class.new(nil, waba_id, access_token)
        expect { service_invalid.perform }.to raise_error(ArgumentError, 'Channel is required')
      end

      it 'raises error when waba_id is blank' do
        service_invalid = described_class.new(channel, '', access_token)
        expect { service_invalid.perform }.to raise_error(ArgumentError, 'WABA ID is required')
      end

      it 'raises error when access_token is blank' do
        service_invalid = described_class.new(channel, waba_id, '')
        expect { service_invalid.perform }.to raise_error(ArgumentError, 'Access token is required')
      end
    end

    context 'when PIN already exists' do
      before do
        channel.provider_config['verification_pin'] = 123_456
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(false)
        allow(api_client).to receive(:register_phone_number)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'reuses existing PIN' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 123_456)
          expect(SecureRandom).not_to receive(:random_number)
          service.perform
        end
      end
    end

    context 'when webhook setup fails and should trigger reauthorization' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(true)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_raise('Invalid access token')
      end

      it 'raises error with webhook setup failure message' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect { service.perform }.to raise_error('Webhook setup failed')
        end
      end

      it 'logs the webhook setup failure' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(Rails.logger).to receive(:error).with('[WHATSAPP] Webhook setup failed: error_class=RuntimeError')
          expect { service.perform }.to raise_error(/Webhook setup failed/)
        end
      end
    end

    context 'when used during reauthorization flow' do
      let(:existing_channel) do
        create(:channel_whatsapp,
               phone_number: '+1234567890',
               provider_config: {
                 'phone_number_id' => '123456789',
                 'webhook_verify_token' => 'existing_verify_token',
                 'business_id' => 'existing_business_id',
                 'waba_id' => 'existing_waba_id',
                 'source' => 'embedded_signup'
               },
               provider: 'whatsapp_cloud',
               sync_templates: false,
               validate_provider_config: false)
      end
      let(:new_access_token) { 'new_access_token' }
      let(:service_reauth) { described_class.new(existing_channel, waba_id, new_access_token) }

      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(true)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'existing_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
      end

      it 'successfully reauthorizes with new access token' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).not_to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'existing_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service_reauth.perform
        end
      end

      it 'uses the existing webhook verify token during reauthorization' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', anything, 'existing_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service_reauth.perform
        end
      end
    end

    context 'when webhook setup is successful in creation flow' do
      before do
        allow(api_client).to receive(:phone_number_verified?).with('123456789').and_return(true)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
      end

      it 'completes successfully without errors' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect { service.perform }.not_to raise_error
        end
      end

      it 'does not log any errors' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(Rails.logger).not_to receive(:error)
          service.perform
        end
      end
    end
  end
end
