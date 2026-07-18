# frozen_string_literal: true

class Internal::UnoPremiumFeaturesHealthCheckService
  EXPECTED_ENABLED_FEATURES = %w[
    disable_branding
    audit_logs
    sla
    custom_roles
    captain_integration
    captain_integration_v2
    captain_document_auto_sync
    csat_review_notes
    conversation_required_attributes
  ].freeze

  EXPECTED_DISABLED_FEATURES = [].freeze

  Result = Struct.new(:errors, keyword_init: true) do
    def ok?
      errors.empty?
    end
  end

  def initialize(account_id: nil)
    @account_id = account_id
    @errors = []
  end

  def perform
    check_installation_config('INSTALLATION_PRICING_PLAN', 'premium')
    check_installation_config('INSTALLATION_PRICING_PLAN_QUANTITY', 1_000_000)
    check_installation_config('CAPTAIN_CLOUD_PLAN_LIMITS', '')
    check_account_level_feature_defaults(EXPECTED_ENABLED_FEATURES, true)
    check_account_level_feature_defaults(EXPECTED_DISABLED_FEATURES, false)
    check_account_features

    Result.new(errors: @errors)
  end

  private

  def check_installation_config(name, expected_value)
    config = InstallationConfig.find_by(name: name)

    if config.blank?
      @errors << "#{name} is missing; expected #{expected_value.inspect}"
      return
    end

    actual_value = config.value
    actual_value = actual_value.to_i if expected_value.is_a?(Integer)
    return if actual_value == expected_value

    @errors << "#{name} is #{config.value.inspect}; expected #{expected_value.inspect}"
  end

  def check_account_level_feature_defaults(expected_features, expected_enabled)
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')

    if config.blank? || config.value.blank?
      @errors << 'ACCOUNT_LEVEL_FEATURE_DEFAULTS is missing or empty'
      return
    end

    defaults = config.value.index_by { |feature| feature['name'] || feature[:name] }

    expected_features.each do |feature_name|
      check_default_feature(defaults, feature_name, expected_enabled)
    end
  end

  def check_default_feature(defaults, feature_name, expected_enabled)
    feature_config = defaults[feature_name]

    if feature_config.blank?
      @errors << "ACCOUNT_LEVEL_FEATURE_DEFAULTS missing #{feature_name}"
      return
    end

    actual_enabled = feature_config['enabled']
    actual_enabled = feature_config[:enabled] if actual_enabled.nil?
    return if actual_enabled == expected_enabled

    @errors << "ACCOUNT_LEVEL_FEATURE_DEFAULTS #{feature_name} is #{actual_enabled.inspect}; expected #{expected_enabled.inspect}"
  end

  def check_account_features
    scope = Account.order(:id)
    scope = scope.where(id: @account_id) if @account_id.present?

    if @account_id.present? && scope.none?
      @errors << "Account #{@account_id} was not found"
      return
    end

    collect_account_feature_errors(scope)
  end

  def collect_account_feature_errors(scope)
    account_count = 0
    missing_enabled = Hash.new { |hash, key| hash[key] = [] }
    wrongly_enabled = Hash.new { |hash, key| hash[key] = [] }
    available_enabled_features = available_features(EXPECTED_ENABLED_FEATURES)
    available_disabled_features = available_features(EXPECTED_DISABLED_FEATURES)

    scope.find_each do |account|
      account_count += 1
      collect_missing_enabled_features(account, available_enabled_features, missing_enabled)
      collect_wrongly_enabled_features(account, available_disabled_features, wrongly_enabled)
    end

    @errors << 'No accounts found to validate' if account_count.zero?
    append_feature_errors(missing_enabled, 'disabled but should be enabled')
    append_feature_errors(wrongly_enabled, 'enabled but should be disabled')
  end

  def collect_missing_enabled_features(account, feature_names, missing_enabled)
    feature_names.each do |feature_name|
      next if account.feature_enabled?(feature_name)

      missing_enabled[feature_name] << account.id
    end
  end

  def collect_wrongly_enabled_features(account, feature_names, wrongly_enabled)
    feature_names.each do |feature_name|
      next unless account.feature_enabled?(feature_name)

      wrongly_enabled[feature_name] << account.id
    end
  end

  def available_features(feature_names)
    feature_names.select { |feature_name| Account.new.respond_to?("feature_#{feature_name}?") }
  end

  def append_feature_errors(feature_accounts, message)
    feature_accounts.each do |feature_name, account_ids|
      sample_ids = account_ids.first(10).join(', ')
      extra_count = account_ids.size - 10
      suffix = extra_count.positive? ? " and #{extra_count} more" : ''

      @errors << "#{feature_name} is #{message} for account ids #{sample_ids}#{suffix}"
    end
  end
end
