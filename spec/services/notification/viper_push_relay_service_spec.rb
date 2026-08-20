require 'rails_helper'

describe Notification::ViperPushRelayService do
  let(:notification) { create(:notification) }
  let(:subscription) do
    create(
      :notification_subscription,
      user: notification.user,
      subscription_type: 'viper_native',
      subscription_attributes: {
        push_token: 'fcm-token',
        device_id: 'installation:device',
        platform: 'android'
      }
    )
  end

  describe '#perform' do
    it 'removes a permanently invalid native subscription' do
      response = instance_double(HTTParty::Response, code: 410)
      allow(HTTParty).to receive(:post).and_return(response)

      with_modified_env VIPER_PUSH_RELAY_URL: 'https://relay.example.test/v1/push', VIPER_PUSH_RELAY_TOKEN: 'relay-token' do
        expect(described_class.new(notification: notification, subscription: subscription).perform).to be(false)
      end

      expect(NotificationSubscription.exists?(subscription.id)).to be(false)
    end

    it 'preserves the subscription after a temporary relay failure' do
      response = instance_double(HTTParty::Response, code: 503, success?: false)
      allow(HTTParty).to receive(:post).and_return(response)

      with_modified_env VIPER_PUSH_RELAY_URL: 'https://relay.example.test/v1/push', VIPER_PUSH_RELAY_TOKEN: 'relay-token' do
        expect do
          described_class.new(notification: notification, subscription: subscription).perform
        end.to raise_error('Viper Push Relay returned HTTP 503')
      end

      expect(NotificationSubscription.exists?(subscription.id)).to be(true)
    end
  end
end
