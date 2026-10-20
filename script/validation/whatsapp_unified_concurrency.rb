# Standalone diagnostic CLI: retain machine-readable stdout, exit status and atomic fixture scenarios.
# rubocop:disable Metrics/BlockLength
unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'viperchat_unified_inbox_test'
  raise 'Wrong database: refusing concurrent validation'
end

require 'factory_bot_rails'
require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
ActiveJob::Base.queue_adapter = :test
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:account)

checks = []
%i[meta uno].product(%w[incoming echo]).each do |principal, direction|
  account = FactoryBot.create(:account)
  suffix = SecureRandom.random_number(10**7).to_s.rjust(7, '0')
  meta = FactoryBot.create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: "+55659#{suffix}",
                                              sync_templates: false, validate_provider_config: false)
  uno = FactoryBot.create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: "+556599#{suffix}",
                                             sync_templates: false, validate_provider_config: false)
  channels = { meta: meta, uno: uno }
  contact = FactoryBot.create(:contact, account: account, phone_number: '+5565987654321', bsuid: 'preserved@lid')
  FactoryBot.create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: '556587654321')
  FactoryBot.create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '5565987654321')
  link = WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                   secondary_inbox: channels.fetch(principal == :meta ? :uno : :meta).inbox,
                                   default_provider: 'unoapi', enabled: true)
  ready = Queue.new
  start = Queue.new
  errors = Queue.new
  threads = channels.map do |provider, channel|
    payload = JSON.parse(Rails.root.join("spec/fixtures/whatsapp_coexistence/#{provider}_phone_#{direction}.json").read)
    value = payload.fetch('entry').first.fetch('changes').first.fetch('value')
    value.fetch('metadata').merge!('display_phone_number' => channel.phone_number.delete_prefix('+'),
                                   'phone_number_id' => channel.provider_config['phone_number_id'])
    events = value['messages'] || value.fetch('message_echoes')
    events.each do |event|
      event['timestamp'] = (Time.current.to_i + 2).to_s
      event['from'] = channel.phone_number.delete_prefix('+') if direction == 'echo'
    end
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ready << true
        start.pop
        retries = 0
        begin
          service = provider == :meta ? Whatsapp::IncomingMessageWhatsappCloudService : Whatsapp::IncomingMessageUnoapiService
          service.new(inbox: Inbox.find(channel.inbox.id), params: payload.deep_dup.with_indifferent_access,
                      outgoing_echo: direction == 'echo').perform
        rescue Whatsapp::UnifiedMessageIngestionService::Busy
          raise if (retries += 1) > 40

          sleep 0.05
          retry
        end
      end
    rescue StandardError => e
      errors << e
    end
  end
  2.times { ready.pop }
  2.times { start << true }
  threads.each { |thread| raise 'Concurrent workers did not finish' unless thread.join(15) }
  raise errors.pop unless errors.empty?

  messages = account.messages.where(message_type: %i[incoming outgoing], private: false)
  raise 'Duplicate or missing canonical message' unless messages.count == 1
  raise 'Wrong principal' unless messages.sole.inbox_id == link.primary_inbox_id
  raise 'Duplicate contact or changed legacy identity' unless account.contacts.count == 1 && contact.reload.bsuid == 'preserved@lid'

  canonical = WhatsappUnifiedMessage.find_by!(message: messages.sole)
  raise 'Missing aliases' unless canonical.aliases.count == 2

  checks << { principal: principal, direction: direction, independent_connections: 2, messages: 1, contacts: 1, aliases: 2 }
end
puts({ result: 'PASS', scenarios: checks }.to_json)

# rubocop:enable Metrics/BlockLength
