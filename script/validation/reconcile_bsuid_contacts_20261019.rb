# Standalone diagnostic CLI: retain machine-readable stdout, exit status and atomic fixture scenarios.
# rubocop:disable Rails/Output
# Preview by default. Apply only in the explicitly authorized deployment window,
# after backup, using the fingerprint returned by a freshly reviewed preview.
require_relative '../../config/environment'
ActiveRecord::Base.logger = nil
raise 'Unexpected database' unless ActiveRecord::Base.connection.current_database == 'chatwoot_db'

link = WhatsappInboxLink.find(1)
raise 'Unexpected inbox pair' unless link.account_id == 1 && link.primary_inbox_id == 1 && link.secondary_inbox_id == 65

pairs = [[107_089, 15_753], [107_090, 4540], [107_092, 9560], [107_095, 13], [107_096, 35], [107_097, 3477]]
service = Whatsapp::ContactReconciliationService.new(link: link, pairs: pairs)
if ENV['APPLY_RECONCILIATION'] == 'yes'
  local_time = Time.current.in_time_zone('America/Cuiaba')
  raise 'Outside the authorized deployment window' unless local_time.to_date == Date.new(2026, 10, 19) && local_time.hour >= 12
  raise 'Explicit preview fingerprint required' if ENV['RECONCILIATION_FINGERPRINT'].blank?

  puts JSON.pretty_generate(service.apply!(fingerprint: ENV.fetch('RECONCILIATION_FINGERPRINT')))
else
  ActiveRecord::Base.transaction do
    ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY')
    puts JSON.pretty_generate(service.preview)
  end
end

# rubocop:enable Rails/Output
