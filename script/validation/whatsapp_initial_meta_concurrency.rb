# Standalone diagnostic CLI: retain machine-readable stdout, exit status and atomic fixture scenarios.
# rubocop:disable Metrics/BlockLength
# Run only in a newly created disposable database; never in the dev replica.
unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'viperchat_initial_meta_concurrency_test'
  raise 'Wrong database: refusing initial Meta concurrency validation'
end
raise 'Concurrency database must start empty' if Account.exists?

require 'factory_bot_rails'
require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
ActiveJob::Base.queue_adapter = :test
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:account)

checks = %w[unoapi whatsapp_cloud].map do |principal|
  account = FactoryBot.create(:account)
  agent = FactoryBot.create(:user, account: account)
  suffix = SecureRandom.random_number(10**7).to_s.rjust(7, '0')
  channels = %w[unoapi whatsapp_cloud].index_with do |provider|
    phone = provider == 'unoapi' ? "+556599#{suffix}" : "+55659#{suffix}"
    FactoryBot.create(:channel_whatsapp, account: account, provider: provider, phone_number: phone,
                                         sync_templates: false, validate_provider_config: false)
  end
  link = WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                   secondary_inbox: channels.except(principal).values.sole.inbox, default_provider: 'unoapi', enabled: true,
                                   meta_initial_messages_enabled: true, meta_initial_messages_limit: 2)
  contact = FactoryBot.create(:contact, account: account, phone_number: '+5565987654321')
  aliases = channels.transform_values do |channel|
    FactoryBot.create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '5565987654321')
  end
  conversation = FactoryBot.create(:conversation, account: account, inbox: link.primary_inbox, contact: contact,
                                                  contact_inbox: aliases.fetch(principal))
  FactoryBot.create(:message, account: account, inbox: channels.fetch('whatsapp_cloud').inbox,
                              conversation: conversation, sender: contact, message_type: :incoming)
  messages = Array.new(4) do
    Messages::MessageBuilder.new(agent, conversation, { content: 'Synthetic concurrent policy', whatsapp_transport: 'unoapi' }).perform
  end
  ready = Queue.new
  start = Queue.new
  errors = Queue.new
  connections = Queue.new
  threads = messages.map do |message|
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connections << connection.select_value('SELECT pg_backend_pid()')
        ready << true
        start.pop
        Whatsapp::InitialMetaMessagesService.new(message: Message.find(message.id)).perform
      end
    rescue StandardError => e
      errors << e
    end
  end
  4.times { ready.pop }
  4.times { start << true }
  threads.each { |thread| raise 'Concurrent policy workers did not finish' unless thread.join(15) }
  raise errors.pop unless errors.empty?
  raise 'Connections were not independent' unless Array.new(4) { connections.pop }.uniq.size == 4

  providers = messages.map { |message| message.reload.content_attributes.dig('whatsapp_transport', 'provider') }.tally
  slots = WhatsappMetaCycleSlot.where(conversation: conversation)
  raise 'Policy quota exceeded or missing' unless providers == { 'whatsapp_cloud' => 2, 'unoapi' => 2 } && slots.count == 2

  messages.each { |message| Whatsapp::InitialMetaMessagesService.new(message: message.reload).perform }
  raise 'Replay spent another slot' unless slots.count == 2
  raise 'Policy changed public IDs' unless messages.all? { |message| message.source_id.nil? }

  { principal: principal, independent_connections: 4, messages: 4, meta_slots: 2, replay_slots: slots.count }
end
puts({ result: 'PASS', scenarios: checks }.to_json) # rubocop:disable Rails/Output

# rubocop:enable Metrics/BlockLength
