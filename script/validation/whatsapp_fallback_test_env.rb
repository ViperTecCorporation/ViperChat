# Run only inside the local replica, with its normally configured credentials.
# DATABASE_URL overrides database.yml, including POSTGRES_DATABASE: change its
# database explicitly before invoking Rails/RSpec. Never print either URL.
require 'uri'

abort 'Test environment required' unless ENV['RAILS_ENV'] == 'test'
abort 'Dedicated database required' unless ENV['POSTGRES_DATABASE'] == 'viperchat_fallback_test'

database = URI.parse(ENV.fetch('DATABASE_URL'))
database.path = '/viperchat_fallback_test'
ENV['DATABASE_URL'] = database.to_s
redis = URI.parse(ENV.fetch('REDIS_URL'))
redis.path = '/14'
ENV['REDIS_URL'] = redis.to_s
exec(*ARGV)
