module Featurable
  extend ActiveSupport::Concern

  module SelectedFeatureFlagsOverride
    def selected_feature_flags
      FEATURE_NAMES.select { |flag| public_send("#{flag}?") }
    end

    def selected_feature_flags=(flags)
      feature_names = FEATURE_LIST.pluck('name')
      disable_features(*feature_names)

      Array(flags).map(&:to_sym).each do |flag|
        next unless FEATURE_NAMES.include?(flag)

        public_send("#{flag}=", true)
      end
    end
  end

  QUERY_MODE = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  FEATURE_LIST = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze
  MAX_FLAGS_PER_COLUMN = 63

  FEATURE_NAMES = FEATURE_LIST.map { |feature| "feature_#{feature['name']}".to_sym }.freeze

  PRIMARY_FEATURES = FEATURE_NAMES.first(MAX_FLAGS_PER_COLUMN)
  SECONDARY_FEATURES = FEATURE_NAMES.drop(MAX_FLAGS_PER_COLUMN)

  PRIMARY_FLAGS = PRIMARY_FEATURES.each_with_index.to_h { |name, index| [index + 1, name] }.freeze
  SECONDARY_FLAGS = SECONDARY_FEATURES.each_with_index.to_h { |name, index| [index + 1, name] }.freeze

  included do
    include FlagShihTzu
    has_flags PRIMARY_FLAGS.merge(column: 'feature_flags').merge(QUERY_MODE)
    has_flags SECONDARY_FLAGS.merge(column: 'feature_flags_2').merge(QUERY_MODE) if SECONDARY_FLAGS.any?

    before_create :enable_default_features
    prepend SelectedFeatureFlagsOverride
  end

  def enable_features(*names)
    known_features(names).each do |name|
      send("feature_#{name}=", true)
    end
  end

  def enable_features!(*names)
    enable_features(*names)
    save
  end

  def disable_features(*names)
    known_features(names).each do |name|
      send("feature_#{name}=", false)
    end
  end

  def disable_features!(*names)
    disable_features(*names)
    save
  end

  def feature_enabled?(name)
    # Force-enable advanced search flags across all accounts.
    return true if %w[advanced_search advanced_search_indexing].include?(name.to_s)
    return false unless known_feature?(name)

    send("feature_#{name}?")
  end

  def all_features
    FEATURE_LIST.pluck('name').index_with do |feature_name|
      feature_enabled?(feature_name)
    end
  end

  def enabled_features
    all_features.select { |_feature, enabled| enabled == true }
  end

  def disabled_features
    all_features.select { |_feature, enabled| enabled == false }
  end

  private

  def enable_default_features
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return true if config.blank?

    features_to_enabled = config.value.select { |f| f[:enabled] }.pluck(:name)
    enable_features(*features_to_enabled)
  end

  def known_features(names)
    names.select { |name| known_feature?(name) }
  end

  def known_feature?(name)
    FEATURE_NAMES.include?("feature_#{name}".to_sym)
  end
end
