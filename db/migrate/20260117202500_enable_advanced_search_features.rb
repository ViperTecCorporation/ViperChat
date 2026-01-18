class EnableAdvancedSearchFeatures < ActiveRecord::Migration[7.0]
  FEATURES_TO_ENABLE = %w[
    advanced_search
    advanced_search_indexing
  ].freeze

  def up
    enable_defaults_in_installation_config
    enable_features_on_existing_accounts
    GlobalConfig.clear_cache
  end

  def down
    # no-op
  end

  private

  def enable_defaults_in_installation_config
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.blank? || config.value.blank?

    features = config.value.map do |feature|
      if FEATURES_TO_ENABLE.include?(feature['name'])
        feature.merge('enabled' => true)
      else
        feature
      end
    end

    config.value = features
    config.save!
  end

  def enable_features_on_existing_accounts
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each do |account|
        account.enable_features!(*FEATURES_TO_ENABLE)
      end
    end
  end
end
