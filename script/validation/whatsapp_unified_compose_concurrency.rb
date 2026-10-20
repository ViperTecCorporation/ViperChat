# Standalone diagnostic CLI: retain machine-readable stdout, exit status and atomic fixture scenarios.
# rubocop:disable Metrics/BlockLength
# Fresh disposable database only; no provider calls or live queues are allowed.
unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'viperchat_unified_compose_concurrency_test'
  raise 'Wrong database: refusing unified compose concurrency validation'
end
raise 'Validation database must start empty' if Account.exists?

require 'factory_bot_rails'
require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
ActiveJob::Base.queue_adapter = :test
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:account)

checks = %w[unoapi whatsapp_cloud].flat_map do |principal|
  account = FactoryBot.create(:account)
  agent = FactoryBot.create(:user, account: account)
  suffix = SecureRandom.random_number(10**7).to_s.rjust(7, '0')
  channels = %w[unoapi whatsapp_cloud].index_with do |provider|
    phone = provider == 'unoapi' ? "+556599#{suffix}" : "+55659#{suffix}"
    FactoryBot.create(:channel_whatsapp, account: account, provider: provider, phone_number: phone,
                                         sync_templates: false, validate_provider_config: false)
  end
  link = WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                   secondary_inbox: channels.except(principal).values.sole.inbox,
                                   default_provider: 'unoapi', enabled: true)
  Array.new(5) do |index|
    unique = index.even?
    link.primary_inbox.update!(lock_to_single_conversation: unique)
    contact = FactoryBot.create(:contact, account: account, phone_number: "+556598765#{index.to_s.rjust(4, '0')}")
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    errors = Queue.new
    threads = Array.new(4) do |position|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ready << true
          start.pop
          ci = Whatsapp::OperationalInboxService.contact_inbox(contact: Contact.find(contact.id), inbox: Inbox.find(link.secondary_inbox_id))
          conversation = ConversationBuilder.new(contact_inbox: ci, params: { assignee_id: agent.id }).perform
          provider = position.even? ? 'unoapi' : 'whatsapp_cloud'
          message = Messages::MessageBuilder.new(agent, conversation, { content: 'Synthetic compose', whatsapp_transport: provider }).perform
          results << { conversation_id: conversation.id, message_id: message.id, provider: provider,
                       connection: connection.select_value('SELECT pg_backend_pid()') }
        end
      rescue StandardError => e
        errors << e
      end
    end
    4.times { ready.pop }
    4.times { start << true }
    threads.each { |thread| raise 'Compose workers did not finish' unless thread.join(15) }
    raise errors.pop unless errors.empty?

    rows = Array.new(4) { results.pop }
    raise 'Connections were not independent' unless rows.pluck(:connection).uniq.size == 4
    raise 'Duplicate conversations' unless rows.pluck(:conversation_id).uniq.one?
    raise 'Duplicate contact inboxes' unless contact.contact_inboxes.where(inbox_id: link.primary_inbox_id).count == 1

    conversation = Conversation.find(rows.first.fetch(:conversation_id))
    raise 'Wrong principal or message count' unless conversation.inbox_id == link.primary_inbox_id && conversation.messages.count == 4

    rows.each do |row|
      message = Message.find(row.fetch(:message_id))
      raise 'Transport was lost' unless message.content_attributes.dig('whatsapp_transport', 'requested_provider') == row.fetch(:provider)
      raise 'Public provider ID invented' if message.source_id.present?
    end
    original_ids = conversation.messages.ids.sort
    conversation.resolved!
    next_conversation = ConversationBuilder.new(contact_inbox: conversation.contact_inbox, params: { assignee_id: agent.id }).perform
    raise 'Wrong cycle behavior' unless (next_conversation.id == conversation.id) == unique
    raise 'Existing message IDs changed' unless conversation.messages.ids.sort == original_ids
    raise 'Resolved history reopened unexpectedly' if !unique && !conversation.reload.resolved?

    { principal: principal, unique: unique, independent_connections: 4, intended_messages: 4, conversations_during_race: 1 }
  end
end
puts({ result: 'PASS', synthetic_contacts: checks.size, scenarios: checks }.to_json)

# rubocop:enable Metrics/BlockLength
