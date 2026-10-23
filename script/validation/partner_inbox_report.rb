# Local replica only. Synthetic records are rolled back in the dedicated test database.
require 'uri'
abort 'Dedicated test environment required' unless ENV['RAILS_ENV'] == 'test' && ENV['POSTGRES_DATABASE'] == 'viperchat_voip_test'
database = URI.parse(ENV.fetch('DATABASE_URL'))
database.path = '/viperchat_voip_test'
ENV['DATABASE_URL'] = database.to_s
redis = URI.parse(ENV.fetch('REDIS_URL'))
redis.path = '/15'
ENV['REDIS_URL'] = redis.to_s
require_relative '../../config/environment'
abort 'Wrong database' unless ActiveRecord::Base.connection.current_database == 'viperchat_voip_test'
require 'factory_bot_rails'
FactoryBot.find_definitions if FactoryBot.factories.count.zero?

checks = []
check = lambda do |name, condition|
  raise "Failed: #{name}" unless condition

  checks << name
end
zone = ActiveSupport::TimeZone['America/Cuiaba']
time = zone.parse('2026-10-01 12:00:00')
base = { business_phone: '5566995554300', contact_id: 1, provider: 'whatsapp_cloud', delivered: true,
         direction: 'outgoing', category: 'service' }
rows = (1..1000).map { |id| base.merge(id: id, created_at: time + id.seconds) }
rows << base.merge(id: 1001, created_at: zone.parse('2026-10-20 12:00:00'))
service = Whatsapp::PartnerCostSimulationService.new(timezone: 'America/Cuiaba', rates: { 'service' => BigDecimal('0.04') })
result = service.perform(rows: rows, since: zone.parse('2026-10-20'), until_time: zone.parse('2026-10-21'))
check.call('monthly_prefix_consumed', result[:chargeable] == 1 && result[:free_allowance].zero? && result[:estimated_cost] == '0.04')
rows << base.merge(id: 1002, created_at: zone.parse('2026-11-01'))
result = service.perform(rows: rows, since: zone.parse('2026-10-01'), until_time: zone.parse('2026-11-02'))
check.call('monthly_reset_no_rollover', result[:free_allowance] == 1001 && result[:chargeable] == 1 &&
                                      result[:months].last[:allowance_remaining] == 999)
rows = [base.merge(id: 1, direction: 'incoming', ad_referral: true, created_at: time),
        base.merge(id: 2, created_at: time + 1.minute), base.merge(id: 3, created_at: time + 7.days),
        base.merge(id: 4, created_at: time + 7.days + 1.minute)]
result = service.perform(rows: rows, since: time, until_time: time + 9.days)
check.call('ad_window_exclusive_end', result[:free_ad] == 2 && result[:free_allowance] == 1 && result[:months].first[:service_delivered] == 1)
rows[1][:created_at] = time + 25.hours
result = service.perform(rows: rows, since: time, until_time: time + 9.days)
check.call('ad_first_reply_deadline', result[:free_ad].zero?)
result = Whatsapp::PartnerCostSimulationService.new(timezone: 'America/Cuiaba', rates: {}).perform(
  rows: [base.merge(id: 1, created_at: time, category: 'marketing')], since: time, until_time: time + 1.day
)
check.call('blank_rate_is_unknown', result[:unpriced] == 1)
result = Whatsapp::PartnerCostSimulationService.new(timezone: 'America/Cuiaba', rates: { 'marketing' => BigDecimal(0) }).perform(
  rows: [base.merge(id: 1, created_at: time, category: 'marketing')], since: time, until_time: time + 1.day
)
check.call('zero_rate_is_explicit', result[:unpriced].zero? && result[:estimated_cost] == '0.0')
rows = [base.merge(id: 1, direction: 'incoming', created_at: time),
        base.merge(id: 2, category: 'utility', template: true, created_at: time + 1.minute),
        base.merge(id: 3, category: nil, template: true, created_at: time + 2.minutes)]
result = service.perform(rows: rows, since: time, until_time: time + 1.day)
check.call('utility_free_in_customer_window', result[:free_customer_window] == 1 && result[:chargeable].zero?)
check.call('unknown_template_not_service', result[:unclassified] == 1 && result[:free_allowance].zero?)
rows = [base.merge(id: 1, created_at: Time.utc(2026, 11, 1, 3, 59, 59)),
        base.merge(id: 2, created_at: Time.utc(2026, 11, 1, 4, 0, 0))]
result = service.perform(rows: rows, since: zone.parse('2026-10-31'), until_time: zone.parse('2026-11-02'))
check.call('waba_midnight_not_utc', result[:months].map { |row| row[:month] } == %w[2026-10 2026-11])
rows = [base.merge(id: 1, created_at: time), base.merge(id: 2, business_phone: '5581988985300', created_at: time + 1.second)]
result = service.perform(rows: rows, since: time, until_time: time + 1.day)
check.call('allowance_per_business_number', result[:months].size == 2 && result[:months].all? { |row| row[:allowance_used] == 1 })

ActiveRecord::Base.transaction do
  account = FactoryBot.create(:account)
  phone = "+556699#{SecureRandom.random_number(10_000_000).to_s.rjust(7, '0')}"
  uno = FactoryBot.create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: phone,
                                           sync_templates: false, validate_provider_config: false).reload.inbox
  meta = FactoryBot.create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: phone,
                                            sync_templates: false, validate_provider_config: false).reload.inbox
  link = WhatsappInboxLink.create!(account: account, primary_inbox: uno, secondary_inbox: meta, default_provider: 'unoapi', enabled: true)
  contact = FactoryBot.create(:contact, account: account)
  conversation = FactoryBot.create(:conversation, account: account, inbox: uno, contact: contact)
  incoming = FactoryBot.create(:message, account: account, inbox: uno, conversation: conversation, sender: contact,
                                        message_type: :incoming, source_id: SecureRandom.uuid, created_at: time)
  unified = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: incoming, original_id: SecureRandom.hex(10),
                                           direction: 'incoming', participant_key: 'phone:test', message_kind: 'text', state: 'committed')
  incoming.update_columns(content_attributes: { whatsapp_unified_message_id: unified.id })
  %w[unoapi whatsapp_cloud].each do |provider|
    inbox = provider == 'unoapi' ? uno : meta
    identity = WhatsappMessageIdentity.create!(account: account, inbox: inbox, channel: inbox.channel, provider: provider,
                                               external_id: SecureRandom.uuid, observations: { 'direction' => 'incoming' })
    WhatsappUnifiedMessageAlias.create!(whatsapp_unified_message: unified, whatsapp_message_identity: identity)
  end
  outgoing = FactoryBot.create(:message, account: account, inbox: uno, conversation: conversation, message_type: :outgoing,
                                        status: :delivered, source_id: SecureRandom.uuid, created_at: time + 5.minutes,
                                        content_attributes: { whatsapp_transport: { provider: 'unoapi' } })
  unified = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: outgoing, original_id: SecureRandom.hex(10),
                                           direction: 'outgoing', participant_key: 'phone:test', message_kind: 'text', state: 'committed')
  identity = WhatsappMessageIdentity.create!(account: account, inbox: meta, channel: meta.channel, provider: 'whatsapp_cloud',
                                             external_id: 'wamid.test', observations: { 'direction' => 'outgoing', 'origin' => 'webhook' })
  WhatsappUnifiedMessageAlias.create!(whatsapp_unified_message: unified, whatsapp_message_identity: identity)
  FactoryBot.create(:message, account: account, inbox: uno, conversation: conversation, message_type: :outgoing, status: :delivered,
                             created_at: time + 6.minutes, content_attributes: { whatsapp_transport: { provider: 'whatsapp_cloud' },
                             whatsapp_delivery: { unoapi: { state: 'failed' }, whatsapp_cloud: { state: 'delivered', origin: 'webhook' } } })
  FactoryBot.create(:message, account: account, inbox: uno, conversation: conversation, message_type: :outgoing, status: :failed,
                             created_at: time + 7.minutes, content_attributes: { whatsapp_transport: { provider: 'whatsapp_cloud' },
                             whatsapp_delivery: { whatsapp_cloud: { state: 'failed' } } })
  FactoryBot.create(:message, account: account, inbox: uno, conversation: conversation, private: true, created_at: time + 8.minutes)
  params = { from: '2026-10-01', to: '2026-10-31', timezone: 'America/Cuiaba', service_rate: '0.04' }
  result = Whatsapp::PartnerInboxReportService.new(account: account, params: params).perform
  check.call('unique_public_messages', result[:totals]['unique_messages'] == 4)
  check.call('incoming_provider_observations', result[:totals]['unoapi'][:incoming] == 1 && result[:totals]['whatsapp_cloud'][:incoming] == 1)
  check.call('meta_echo_not_another_send', result[:totals]['unoapi'][:outgoing] == 1 && result[:totals]['whatsapp_cloud'][:outgoing] == 2)
  check.call('failed_send_not_billable', result[:totals]['whatsapp_cloud'][:delivered] == 1 && result[:simulation][:free_allowance] == 1)
  proof = WhatsappMessageIdentity.create!(account: account, inbox: uno, channel: uno.channel, provider: 'unoapi',
    external_id: SecureRandom.uuid, observations: { 'origin' => 'api_response', 'direction' => 'outgoing' })
  direct_alias = WhatsappUnifiedMessageAlias.create!(message: outgoing, whatsapp_message_identity: proof)
  outgoing.update_columns(content_attributes: {})
  result = Whatsapp::PartnerInboxReportService.new(account: account, params: params).perform
  check.call('direct_alias_api_evidence', result[:totals]['unoapi'][:outgoing] == 1)
  direct_alias.destroy!
  outgoing.update_columns(source_id: 'wamid.historical-echo')
  result = Whatsapp::PartnerInboxReportService.new(account: account, params: params).perform
  check.call('wamid_alone_is_not_meta_send', result[:totals]['unknown'][:outgoing] == 1 && result[:totals]['whatsapp_cloud'][:outgoing] == 2)
  check.call('missing_timezone_disables_estimate', Whatsapp::PartnerInboxReportService.new(account: account,
    params: params.except(:timezone)).perform[:simulation].nil?)
  foreign = FactoryBot.create(:account)
  check.call('account_isolation', Whatsapp::PartnerInboxReportService.new(account: foreign, params: params.merge(link_id: link.id)).perform[:pairs].empty?)
  %w[-1 NaN Infinity].each do |rate|
    begin
      Whatsapp::PartnerInboxReportService.new(account: account, params: params.merge(service_rate: rate))
      raise 'Invalid rate accepted'
    rescue Whatsapp::PartnerInboxReportService::InvalidParameters
      checks << "invalid_rate_#{rate}"
    end
  end
  admin = FactoryBot.create(:user, account: account, role: :administrator)
  agent = FactoryBot.create(:user, account: account, role: :agent)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  path = "/api/v2/accounts/#{account.id}/reports/partner_inboxes"
  session.get(path, params: params, headers: admin.create_new_auth_token)
  check.call('api_admin_authorized', session.response.status == 200 && session.response.parsed_body['totals']['unique_messages'] == 4)
  session.get(path, params: params, headers: agent.create_new_auth_token)
  check.call('api_agent_forbidden', session.response.status.in?([401, 403]))
  session.get(path, params: params)
  check.call('api_auth_required', session.response.status == 401)
  raise ActiveRecord::Rollback
end
puts JSON.generate(passed: checks.size, checks: checks)
