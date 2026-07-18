require 'rails_helper'

RSpec.describe I18n do
  def leaf_keys(value, prefix = nil)
    return [prefix] unless value.is_a?(Hash)

    value.flat_map do |key, child|
      leaf_keys(child, [prefix, key].compact.join('.'))
    end
  end

  it 'has a pt_BR translation for every English Super Admin key' do
    english_keys = leaf_keys(described_class.t('super_admin', locale: :en))
    missing_keys = english_keys.reject do |key|
      described_class.exists?("super_admin.#{key}", :pt_BR, fallback: false)
    end

    expect(missing_keys).to be_empty
  end

  it 'translates every Administrate resource exposed by the Super Admin' do
    resources = %w[accounts users access_tokens installation_configs agent_bots platform_apps platform_banners account_users]
    missing_keys = resources.reject do |resource|
      described_class.exists?("administrate.resources.#{resource}.name", :pt_BR, fallback: false)
    end

    expect(missing_keys).to be_empty
  end
end
