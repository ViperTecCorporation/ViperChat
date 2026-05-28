class WebhookJob < ApplicationJob
  queue_as :medium

  # There are 3 types of webhooks: account, inbox and agent_bot.
  def perform(url, payload, webhook_type = :account_webhook, method = :post,
              headers = Webhooks::Trigger::DEFAULT_HEADERS)
    Webhooks::Trigger.execute(url, payload, webhook_type, method, headers)
  end
end
