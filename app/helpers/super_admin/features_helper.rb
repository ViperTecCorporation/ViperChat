module SuperAdmin::FeaturesHelper
  def self.available_features
    features = YAML.load(ERB.new(Rails.root.join('app/helpers/super_admin/features.yml').read).result).with_indifferent_access
    features.each do |key, feature|
      feature[:name] = I18n.t("super_admin.installation_features.#{key}.name", default: feature[:name])
      feature[:description] = I18n.t("super_admin.installation_features.#{key}.description", default: feature[:description])
    end
  end

  def self.plan_details
    plan = ChatwootHub.pricing_plan
    quantity = ChatwootHub.pricing_plan_quantity

    if plan == 'premium'
      I18n.t('super_admin.plan_agents', plan: plan, quantity: quantity)
    else
      I18n.t('super_admin.plan_edition', plan: plan)
    end
  end
end
