module Featurable::Defaults
  def default_feature_names
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    feature_defaults = Array(config&.value).presence || Featurable::FEATURE_LIST

    names = feature_defaults.filter_map do |feature|
      values = feature.with_indifferent_access
      values[:name] if ActiveModel::Type::Boolean.new.cast(values[:enabled])
    end

    # Older installations may not have these entries in their saved defaults.
    configured_names = feature_defaults.map { |feature| feature.with_indifferent_access[:name] }
    names + (%w[advanced_search advanced_search_indexing] - configured_names)
  end

  def default_feature_flags
    default_feature_names.filter_map do |name|
      flag = "feature_#{name}".to_sym
      flag if Featurable::FEATURE_NAMES.include?(flag)
    end
  end
end
