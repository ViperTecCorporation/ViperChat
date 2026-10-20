require 'rails_helper'

# No live Meta credentials or external HTTP. Existing ingestion specs exercise
# the asynchronous batches; these cases cover the missing outbound lifecycle.
# rubocop:disable Rails/SkipsModelValidations
RSpec.describe Whatsapp::SmbAppDataService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:service) { described_class.new(channel: channel) }
  let(:client) { instance_double(Whatsapp::SmbAppDataClient) }
  let(:setup) { instance_double(Whatsapp::WebhookSetupService, register_callback: true) }
  let(:management) { instance_double(Whatsapp::ManagementApiClient) }

  around do |example|
    with_modified_env WHATSAPP_SMB_SYNC_ENABLED: 'true' do
      example.run
    end
  end

  before do
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_history_messages' => false, 'history_max_age_days' => 15))
    allow(Whatsapp::ManagementApiClient).to receive(:new).with(channel).and_return(management)
    allow(management).to receive(:get).and_return('is_on_biz_app' => true, 'platform_type' => 'CLOUD_API')
    allow(Whatsapp::WebhookSetupService).to receive(:new).with(channel).and_return(setup)
    allow(Whatsapp::SmbAppDataClient).to receive(:new).with(channel).and_return(client)
    allow(client).to receive(:request).with('smb_app_state_sync').and_return('contacts-request')
    allow(client).to receive(:request).with('history').and_return('history-request')
  end

  it 'subscribes before requesting contacts and history, preserving credentials and unrelated subscriptions' do
    previous = channel.provider_config.merge('webhook_fields' => ['security'])
    channel.update_column(:provider_config, previous)
    expect(setup).to receive(:register_callback).ordered
    expect(client).to receive(:request).with('smb_app_state_sync').ordered
    expect(client).to receive(:request).with('history').ordered

    service.perform
    expect(channel.reload.provider_config).to eq(previous.merge('webhook_fields' => %w[security history smb_app_state_sync smb_message_echoes]))
    expect(WhatsappSmbSyncRequest.order(:id).pluck(:sync_type, :state, :request_id, :history_max_age_days)).to eq(
      [%w[smb_app_state_sync accepted contacts-request] + [15], %w[history accepted history-request] + [15]]
    )
  end

  it 'does not repeat requests on duplicate jobs, saves or refreshed credentials' do
    service.perform
    channel.update_column(:provider_config, channel.provider_config.merge('api_key' => 'refreshed-test-token', 'history_max_age_days' => 30))
    3.times { service.perform }
    expect(client).to have_received(:request).with('history').once
    expect(client).to have_received(:request).with('smb_app_state_sync').once
    expect(WhatsappSmbSyncRequest.count).to eq(2)
  end

  it 'is disabled by default at deployment, without even probing Meta' do
    with_modified_env WHATSAPP_SMB_SYNC_ENABLED: nil do
      service.perform
    end
    expect(management).not_to have_received(:get)
    expect(client).not_to have_received(:request)
  end

  it 'does not synchronize when history is ignored or reauthorization is required' do
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_history_messages' => true))
    service.perform
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_history_messages' => false))
    allow(channel).to receive(:reauthorization_required?).and_return(true)
    service.perform
    expect(management).not_to have_received(:get)
    expect(WhatsappSmbSyncRequest.count).to eq(0)
  end

  it 'rejects ordinary Cloud numbers before subscriptions or requests' do
    allow(management).to receive(:get).and_return('is_on_biz_app' => false, 'platform_type' => 'CLOUD_API')
    expect { service.perform }.to raise_error(Whatsapp::SmbAppDataService::PreparationError, 'not_coexistence')
    expect(setup).not_to have_received(:register_callback)
    expect(client).not_to have_received(:request)
  end

  it 'does not dispatch anything until subscription succeeds; preparatory failures can safely resume' do
    allow(setup).to receive(:register_callback).and_raise('unsafe response with test-secret')
    expect { service.perform }.to raise_error(Whatsapp::SmbAppDataService::PreparationError, 'webhook_setup_failed')
    expect(WhatsappSmbSyncRequest.count).to eq(0)
    allow(setup).to receive(:register_callback).and_return(true)
    service.perform
    expect(WhatsappSmbSyncRequest.where(state: 'accepted').count).to eq(2)
  end

  it 'journals before the network call and prevents a competing worker from dispatching again' do
    allow(client).to receive(:request).with('smb_app_state_sync') do
      expect(WhatsappSmbSyncRequest.find_by!(sync_type: 'smb_app_state_sync').state).to eq('dispatched')
      described_class.new(channel: channel.reload).perform
      'contacts-request'
    end
    service.perform
    expect(client).to have_received(:request).with('smb_app_state_sync').once
    expect(client).to have_received(:request).with('history').once
  end

  it 'keeps uncertain contact dispatch pending confirmation and never proceeds to history or repeats it' do
    allow(client).to receive(:request).with('smb_app_state_sync').and_raise(
      Whatsapp::SmbAppDataClient::Error.new('delivery_unknown', ambiguous: true)
    )
    2.times { service.perform }
    expect(WhatsappSmbSyncRequest.sole).to have_attributes(state: 'uncertain', request_id: nil, reason: 'delivery_unknown')
    expect(client).not_to have_received(:request).with('history')
    expect(client).to have_received(:request).with('smb_app_state_sync').once
  end

  it 'preserves accepted contacts when Meta rejects history, including an expired onboarding window' do
    allow(client).to receive(:request).with('history').and_raise(
      Whatsapp::SmbAppDataClient::Error.new('request_rejected', ambiguous: false)
    )
    2.times { service.perform }
    expect(WhatsappSmbSyncRequest.find_by!(sync_type: 'smb_app_state_sync').state).to eq('accepted')
    expect(WhatsappSmbSyncRequest.find_by!(sync_type: 'history').state).to eq('rejected')
    expect(client).to have_received(:request).with('history').once
  end

  it 'does not repeat a request after a process crash left the dispatch unacknowledged' do
    WhatsappSmbSyncRequest.create!(account: account, channel: channel, waba_id: channel.provider_config['business_account_id'],
                                   phone_number_id: channel.provider_config['phone_number_id'], sync_type: 'smb_app_state_sync',
                                   history_max_age_days: 7, state: 'dispatched', dispatched_at: 10.minutes.ago)
    service.perform
    expect(client).not_to have_received(:request)
  end

  it 'stops before history if the operator disables import during the first request' do
    allow(client).to receive(:request).with('smb_app_state_sync') do
      channel.update_column(:provider_config, channel.provider_config.merge('ignore_history_messages' => true))
      'contacts-request'
    end
    service.perform
    expect(client).not_to have_received(:request).with('history')
  end

  it 'does not reuse another account or channel journal even when a misconfigured inbox repeats its phone ID' do
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    WhatsappSmbSyncRequest.create!(account: other.account, channel: other, waba_id: 'other-waba',
                                   phone_number_id: channel.provider_config['phone_number_id'], sync_type: 'history',
                                   history_max_age_days: 7, state: 'accepted', request_id: 'private-other-request')
    service.perform
    expect(management).not_to have_received(:get)
    expect(setup).not_to have_received(:register_callback)
    expect(client).not_to have_received(:request)
  end

  it 'stops before dispatch if the business phone identity changes during preparation' do
    allow(setup).to receive(:register_callback) do
      channel.update_column(:provider_config, channel.provider_config.merge('phone_number_id' => 'changed-phone-id'))
    end
    service.perform
    expect(client).not_to have_received(:request)
    expect(WhatsappSmbSyncRequest.sole.state).to eq('prepared')
  end

  it 'does not retarget callbacks if the phone identity changes while Meta coexistence is being checked' do
    allow(management).to receive(:get) do
      channel.update_column(:provider_config, channel.provider_config.merge('phone_number_id' => 'another-phone',
                                                                            'business_account_id' => 'another-waba'))
      { 'is_on_biz_app' => true, 'platform_type' => 'CLOUD_API' }
    end
    service.perform
    expect(setup).not_to have_received(:register_callback)
    expect(client).not_to have_received(:request)
    expect(WhatsappSmbSyncRequest.count).to eq(0)
  end
end
# rubocop:enable Rails/SkipsModelValidations
