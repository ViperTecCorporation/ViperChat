# Standalone diagnostic CLI: retain machine-readable stdout, exit status and atomic fixture scenarios.
# rubocop:disable Rails/Output
raise 'Local dev replica required' unless Rails.env.development? && ActiveRecord::Base.connection.current_database == 'chatwoot_db'

require 'factory_bot_rails'
require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
ActiveJob::Base.queue_adapter = :test
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:account)

if ARGV.first == 'recover_login'
  account = Account.find(Integer(ARGV.fetch(1)))
  super_admin = SuperAdmin.find(Integer(ARGV.fetch(2)))
  raise 'Not the synthetic UI fixture' unless account.name == 'QA temporário — etiquetas e OpenRouter'
  unless super_admin.email.start_with?('qa-label-router-super-') && super_admin.email.end_with?('@example.invalid')
    raise 'Not the synthetic super admin'
  end

  users = account.users.to_a
  raise 'Unexpected fixture member' unless users.all? do |user|
    user.email.start_with?('qa-label-router-') && user.email.end_with?('@example.invalid')
  end

  password = "#{SecureRandom.base64(24)}aA1!"
  (users + [super_admin]).uniq(&:id).each { |user| user.update!(password: password, password_confirmation: password) }
  puts({ account_id: account.id, admin: users.find { |user| user.email.include?('-admin-') }.email,
         agent: users.find { |user| user.email.include?('-agent-') }.email,
         super_admin: super_admin.email, super_admin_id: super_admin.id, password: password }.to_json)
elsif ARGV.first == 'cleanup'
  account = Account.find(Integer(ARGV.fetch(1)))
  raise 'Not the synthetic UI fixture' unless account.name == 'QA temporário — etiquetas e OpenRouter'

  users = account.users.to_a
  raise 'Unexpected fixture member' unless users.all? do |user|
    user.email.start_with?('qa-label-router-') && user.email.end_with?('@example.invalid')
  end
  raise 'Fixture unexpectedly owns content' if account.conversations.exists? || account.attachments.exists? || account.inboxes.exists?

  account.labels.destroy_all
  account.account_users.destroy_all
  account.destroy!
  users.each(&:destroy!)
  super_admin = SuperAdmin.find(Integer(ARGV.fetch(2)))
  raise 'Not the synthetic super admin' unless super_admin.email.start_with?('qa-label-router-') && super_admin.email.end_with?('@example.invalid')

  super_admin.destroy!
  puts({ cleaned: true }.to_json)
else
  password = "#{SecureRandom.base64(24)}aA1!"
  tag = SecureRandom.hex(5)
  account = FactoryBot.create(:account, name: 'QA temporário — etiquetas e OpenRouter')
  account.enable_features!('labels')
  admin = FactoryBot.create(:user, account: account, role: :administrator, email: "qa-label-router-admin-#{tag}@example.invalid", password: password)
  agent = FactoryBot.create(:user, account: account, role: :agent, email: "qa-label-router-agent-#{tag}@example.invalid", password: password)
  super_admin = FactoryBot.create(:super_admin, email: "qa-label-router-super-#{tag}@example.invalid", password: password)
  puts({ account_id: account.id, admin: admin.email, agent: agent.email, super_admin: super_admin.email, super_admin_id: super_admin.id,
         password: password }.to_json)
end

# rubocop:enable Rails/Output
