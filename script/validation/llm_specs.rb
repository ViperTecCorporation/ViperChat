# Standalone diagnostic CLI: retain machine-readable stdout, exit status and atomic fixture scenarios.
# rubocop:disable Rails/Exit
# Isolate pre-existing integration configuration without modifying the dev database.
$LOAD_PATH.unshift(File.expand_path('../../spec', __dir__))
raise 'Test environment required' unless ENV['RAILS_ENV'] == 'test'

require_relative '../../config/environment'
raise 'Isolated test database required' unless Rails.env.test? && ActiveRecord::Base.connection.current_database == 'viperchat_meta_embed_validation'

require_relative '../../spec/rails_helper'

result = nil
ActiveRecord::Base.transaction do
  InstallationConfig.where(name: %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_OPEN_AI_ENDPOINT CAPTAIN_OPEN_AI_MODEL
                                    CAPTAIN_AUDIO_TRANSCRIPTION_MODEL]).delete_all
  Llm::Config.reset!
  result = RSpec::Core::Runner.run(ARGV)
  raise ActiveRecord::Rollback
end
exit result

# rubocop:enable Rails/Exit
