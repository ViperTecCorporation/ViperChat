# Persistent, explicitly requested dev-only fixture. No Meta credentials or HTTP.
unless Rails.env.development? && ActiveRecord::Base.connection_db_config.database == 'chatwoot_db'
  raise 'This fixture can only be created in the local development replica'
end

require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
ActiveJob::Base.queue_adapter = :test

primary = Inbox.find(1)
raise 'Unexpected primary inbox' unless primary.account_id == 1 && primary.name == 'Viper Tec' && primary.channel.provider == 'unoapi'

# The channel phone column is globally unique by raw spelling. The existing
# ViperConnect value stays untouched; the Meta value uses the same E.164 digits
# without '+', already supported by the comparison service.
number = primary.channel.phone_number.delete_prefix('+')
expected_name = 'Meta teste DEV — Viper Tec (sem conexão)'
channel = Channel::Whatsapp.find_by(phone_number: number)
if channel
  raise 'An unrelated channel already owns this number' unless channel.account_id == 1 && channel.provider == 'whatsapp_cloud'
  raise 'Existing inbox is not the requested test fixture' unless channel.inbox&.name == expected_name
else
  ApplicationRecord.transaction do
    channel = Channel::Whatsapp.new(account: primary.account, provider: 'whatsapp_cloud', phone_number: number,
                                    provider_config: { 'source' => 'embedded_signup', 'dev_unified_inbox_fixture' => true })
    # Local to this synthetic instance, not global production callback changes.
    channel.define_singleton_method(:validate_provider_config) { nil }
    channel.define_singleton_method(:sync_templates) { nil }
    channel.save!
    Inbox.create!(account: primary.account, channel: channel, name: expected_name,
                  greeting_enabled: false, enable_auto_assignment: false)
  end
end

raise 'Meta credentials must remain absent' if channel.provider_config.values_at('api_key', 'phone_number_id', 'business_account_id').any?(&:present?)
unless Whatsapp::InboxLinkPhoneService.normalize(channel.phone_number) == Whatsapp::InboxLinkPhoneService.normalize(primary.channel.phone_number)
  raise 'Fixture business number does not match the primary'
end

# rubocop:disable Rails/Output -- Technical fixture result, never credentials.
puts({ inbox_id: channel.inbox.id, account_id: 1, name: channel.inbox.name, phone_number: channel.phone_number,
       provider: channel.provider, meta_connected: false, active_links: WhatsappInboxLink.active.covering(primary.id).count,
       queued_jobs: ActiveJob::Base.queue_adapter.enqueued_jobs.size }.to_json)
# rubocop:enable Rails/Output
