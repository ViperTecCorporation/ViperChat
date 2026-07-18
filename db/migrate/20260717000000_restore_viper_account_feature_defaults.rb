class RestoreViperAccountFeatureDefaults < ActiveRecord::Migration[7.0]
  def up
    features = YAML.safe_load(Rails.root.join('config/features.yml').read)
    config = InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    config.update!(value: features, locked: true)
    GlobalConfig.clear_cache
  end

  def down
    # Keep the configured defaults in place when rolling back application code.
  end
end
