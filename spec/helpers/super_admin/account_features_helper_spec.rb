require 'rails_helper'

RSpec.describe SuperAdmin::AccountFeaturesHelper do
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
