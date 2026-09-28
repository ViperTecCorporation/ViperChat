require 'rails_helper'

RSpec.describe SuperAdmin::AccountFeaturesHelper do
  %i[pt_BR pt].each do |locale|
    it "provides a localized name and explanation for every feature in #{locale}" do
      I18n.with_locale(locale) do
        described_class.account_features.each do |feature|
          expect(I18n.exists?("super_admin.features.#{feature['name']}.name", locale)).to be(true), feature['name']
          expect(described_class.feature_description(feature['name'])).to be_present, feature['name']
        end
      end
    end
  end

  describe '.boolean_enabled?' do
    it 'preserves boolean values' do
      expect(described_class.boolean_enabled?(true)).to be(true)
      expect(described_class.boolean_enabled?(false)).to be(false)
    end

    it 'normalizes serialized checkbox values' do
      expect(described_class.boolean_enabled?('true')).to be(true)
      expect(described_class.boolean_enabled?('false')).to be(false)
      expect(described_class.boolean_enabled?('1')).to be(true)
      expect(described_class.boolean_enabled?('0')).to be(false)
    end

    it 'does not turn missing values into enabled features' do
      expect(described_class.boolean_enabled?(nil)).to be(false)
      expect(described_class.boolean_enabled?('')).to be(false)
    end
  end
end
