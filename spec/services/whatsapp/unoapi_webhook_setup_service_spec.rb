require 'rails_helper'

describe Whatsapp::UnoapiWebhookSetupService do
  subject(:service) { described_class.new }

  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      phone_number: '+5566996222471',
      provider: 'unoapi',
      provider_config: {
        'url' => 'https://uno.example.com',
        'api_key' => 'vipertec',
        'business_account_id' => '5566996222471',
        'webhook_verify_token' => 'c84834e6b008de54e8db97b7b01cc',
        'connect' => true,
        'webhook_send_new_messages' => false,
        'send_transcribe_audio' => true,
        'ignore_group_messages' => true,
        'ignore_broadcast_messages' => true,
        'ignore_broadcast_statuses' => true,
        'ignore_history_messages' => false,
        'ignore_own_messages' => false,
        'ignore_yourself_messages' => false,
        'send_connection_status' => true,
        'notify_failed_messages' => true,
        'composing_message' => false,
        'read_on_receipt' => false,
        'read_on_reply' => true,
        'groq_api_key' => 'gsk-test',
        'send_reaction_as_reply' => true,
        'send_profile_picture' => true
      },
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:register_response) { instance_double(HTTParty::Response, success?: true) }
  let(:message_response) { instance_double(HTTParty::Response, success?: true) }

  before do
    allow(channel).to receive(:save!).and_return(true)
    allow(channel).to receive(:inbox).and_return(
      instance_double('Inbox', name: 'Viper tec Principal', account_id: account.id)
    )
  end

  it 'posts the expected register payload and forces connection defaults' do
    calls = []
    allow(HTTParty).to receive(:post) do |url, options|
      calls << [url, options]
      calls.length == 1 ? register_response : message_response
    end

    with_modified_env FRONTEND_URL: 'https://chatwoot.vipertec.net' do
      service.perform(channel)
    end

    register_url, register_options = calls.first
    payload = JSON.parse(register_options[:body])
    webhook = payload['webhooks'].first

    expect(register_url).to eq('https://uno.example.com/v15.0/5566996222471/register')
    expect(payload['autoConnect']).to be(true)
    expect(payload['useRedis']).to be(true)
    expect(payload['useS3']).to be(true)
    expect(webhook['urlAbsolute']).to eq('https://chatwoot.vipertec.net/webhooks/whatsapp/5566996222471')
    expect(webhook['url']).to be_nil
    expect(webhook['token']).to eq('c84834e6b008de54e8db97b7b01cc')
    expect(webhook['sendNewMessages']).to be(true)
  end
end
