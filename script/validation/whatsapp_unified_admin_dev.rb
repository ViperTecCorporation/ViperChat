# Browser acceptance fixtures only. All provider HTTP and background callbacks
# are disabled while seeding; never run against a production database.
unless Rails.env.development? && ActiveRecord::Base.connection_db_config.database == 'chatwoot_db'
  raise 'Administrative UI fixtures require the local development replica'
end

require 'factory_bot_rails'
require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
ActiveJob::Base.queue_adapter = :test
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:account)

if ARGV.first == 'cleanup'
  account = Account.find(Integer(ARGV.fetch(1)))
  raise 'Not the administrative acceptance fixture' unless account.name == 'QA temporário — revisão unificada'

  users = account.users.to_a
  raise 'Not an isolated fixture user' unless users.all? { |user| user.email.match?(/\Aqa-unified-.*@example.invalid\z/) }
  raise 'Fixture unexpectedly owns files' if account.attachments.exists?

  # Synthetic channel configs must not initiate even a teardown HTTP call.
  account.whatsapp_channels.each { |channel| channel.update_columns(provider_config: {}) } # rubocop:disable Rails/SkipsModelValidations
  WhatsappInboxLink.where(account: account).destroy_all
  # Contact destruction callbacks still need the live parent account.
  account.scheduled_messages.destroy_all
  account.messages.destroy_all
  account.conversations.destroy_all
  account.contacts.destroy_all
  account.inboxes.destroy_all
  account.whatsapp_channels.destroy_all
  account.account_users.destroy_all
  account.destroy!
  # Model dependencies use destroy_async. Drain only those local cleanup jobs,
  # never provider sends, notifications or any other background work.
  drain_cleanup = lambda do
    while (job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |entry| entry[:job].name == 'ActiveRecord::DestroyAssociationAsyncJob' })
      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(job)
      ActiveJob::Base.execute(job)
    end
  end
  drain_cleanup.call
  users.each do |user|
    raise 'Fixture user has other account memberships' if user.account_users.exists?

    user.destroy!
  end
  drain_cleanup.call
  puts({ cleaned_account_id: account.id }.to_json) # rubocop:disable Rails/Output
else
  raise 'Specify seed, seed_schedule, seed_compose or cleanup' unless %w[seed seed_schedule seed_compose].include?(ARGV.first)

  password = "Qa!#{SecureRandom.hex(18)}9a"
  account = FactoryBot.create(:account, name: 'QA temporário — revisão unificada', locale: 'pt_BR')
  account.enable_features!('inbox_management')
  admin = FactoryBot.create(:user, account: account, role: :administrator, name: 'QA revisão administrativa',
                                   email: "qa-unified-#{SecureRandom.hex(6)}@example.invalid", password: password)
  channels = %w[unoapi whatsapp_cloud].map do |provider|
    phone = provider == 'unoapi' ? '+5565997654308' : '+556597654308'
    FactoryBot.create(:channel_whatsapp, account: account, provider: provider, phone_number: phone,
                                         sync_templates: false, validate_provider_config: false)
  end
  uno, meta = channels
  uno.inbox.update!(name: 'QA ViperConnect — sem envios reais')
  meta.inbox.update!(name: 'QA Meta — sem envios reais')
  link = WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox,
                                   default_provider: 'unoapi', enabled: true)
  identity = WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta, provider: 'whatsapp_cloud',
                                             external_id: "wamid.qa-#{SecureRandom.hex(100)}", provider_message_id: 'QA-ADMIN-ORIGINAL')
  WhatsappUnifiedEvent.create!(whatsapp_inbox_link: link, whatsapp_message_identity: identity,
                               activation_cutoff: link.activated_at, state: 'review', reason: 'identity_pending', attempts: 12,
                               payload: { metadata: { display_phone_number: meta.phone_number.delete_prefix('+') }, messages: [] })
  contact_attributes = { account: account, name: 'Contato sintético QA' }
  contact_attributes[:phone_number] = '+5565987654321' if ARGV.first == 'seed_compose'
  contact = FactoryBot.create(:contact, **contact_attributes)
  target_contact = if ARGV.first == 'seed_compose'
                     FactoryBot.create(:contact, account: account, name: 'QA destinatário unificado', phone_number: '+5565987654322')
                   end
  conversation = FactoryBot.create(:conversation, account: account, inbox: uno.inbox, contact: contact)
  FactoryBot.create(:message, account: account, inbox: uno.inbox, conversation: conversation, sender: admin,
                              content: 'Mensagem sintética sem envio ao provedor', message_type: :outgoing,
                              content_attributes: { whatsapp_transport: { link_id: link.id, provider: 'unoapi',
                                                                          delivery_attempt_id: SecureRandom.uuid, delivery_state: 'uncertain' } })
  scheduled = nil
  if ARGV.first == 'seed_schedule'
    label = FactoryBot.create(:label, account: account, title: 'qa-agendamento')
    scheduled = ScheduledMessage.create!(account: account, conversation: conversation, inbox: uno.inbox, contact: contact,
                                         label: label, created_by: admin, sender: admin, scheduled_at: 7.days.from_now,
                                         content: 'Agendamento antigo sintético — não enviar')
    scheduled.items.create!(position: 0, content: scheduled.content, content_type: 'text')
  end
  # Ephemeral fixture credentials go only to the caller, never Rails logs.
  result = { account_id: account.id, inbox_id: uno.inbox.id, email: admin.email, password: password,
             schedule_id: scheduled&.id, scheduled_at: scheduled&.scheduled_at,
             source_conversation_id: conversation.display_id, target_contact_id: target_contact&.id, meta_inbox_id: meta.inbox.id }
  puts(result.to_json) # rubocop:disable Rails/Output
end
