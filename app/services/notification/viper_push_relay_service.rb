class Notification::ViperPushRelayService
  pattr_initialize [:notification!, :subscription!]

  def perform
    response = HTTParty.post(
      ENV.fetch('VIPER_PUSH_RELAY_URL'),
      headers: {
        'Authorization' => "Bearer #{ENV.fetch('VIPER_PUSH_RELAY_TOKEN')}",
        'Content-Type' => 'application/json'
      },
      body: payload.to_json,
      timeout: 10
    )

    raise "Viper Push Relay returned HTTP #{response.code}" unless response.success?
  end

  private

  def payload
    {
      installation_id: ChatwootHub.installation_identifier,
      device: subscription.subscription_attributes.slice('push_token', 'device_id', 'platform'),
      notification: {
        title: notification.browser_push_title,
        body: notification.browser_push_body,
        data: notification.fcm_push_data
      }
    }
  end
end
