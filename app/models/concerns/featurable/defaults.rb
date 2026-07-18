module Featurable::Defaults
  def default_feature_names
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    feature_defaults = Array(config&.value).presence || Featurable::FEATURE_LIST

    feature_defaults.filter_map do |feature|
      values = feature.with_indifferent_access
      values[:name] if ActiveModel::Type::Boolean.new.cast(values[:enabled])
    end
  end

  def default_feature_flags
    default_feature_names.filter_map do |name|
      flag = "feature_#{name}".to_sym
      flag if Featurable::FEATURE_NAMES.include?(flag)
    end
  end
end
