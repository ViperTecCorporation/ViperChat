class WebhookJob < ApplicationJob
  queue_as :medium

  # There are 3 types of webhooks: account, inbox and agent_bot.
  def perform(url, payload, webhook_type = :account_webhook, *args, **kwargs)
    options = extract_keyword_options(args, kwargs)
    method = args[0] || :post
    headers = args[1] || Webhooks::Trigger::DEFAULT_HEADERS

    Webhooks::Trigger.execute(url, payload, webhook_type, method, headers, secret: options[:secret], delivery_id: options[:delivery_id])
  end

  private

  def extract_keyword_options(args, kwargs)
    options = kwargs.to_h.symbolize_keys
    return options unless serialized_keyword_options?(args.last)

    options.reverse_merge!(args.pop.symbolize_keys)
  end

  def serialized_keyword_options?(value)
    return false unless value.is_a?(Hash)

    value.key?(:secret) || value.key?('secret') || value.key?(:delivery_id) || value.key?('delivery_id')
  end
end
