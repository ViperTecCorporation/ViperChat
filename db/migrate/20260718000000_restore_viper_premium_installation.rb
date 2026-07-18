class RestoreViperPremiumInstallation < ActiveRecord::Migration[7.0]
  PREMIUM_CONFIG = {
    'INSTALLATION_PRICING_PLAN' => 'premium',
    'INSTALLATION_PRICING_PLAN_QUANTITY' => 1_000_000,
    'CAPTAIN_CLOUD_PLAN_LIMITS' => ''
  }.freeze

  def up
    PREMIUM_CONFIG.each do |name, value|
      InstallationConfig.find_or_initialize_by(name: name).update!(value: value, locked: true)
    end

    GlobalConfig.clear_cache
  end

  def down
    # ViperChat installations must not be downgraded when application code rolls back.
  end
end
