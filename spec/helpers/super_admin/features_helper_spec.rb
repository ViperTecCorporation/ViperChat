require 'rails_helper'

RSpec.describe SuperAdmin::FeaturesHelper do
  it 'translates every installation feature and its explanation' do
    I18n.with_locale(:pt_BR) do
      described_class.available_features.each do |key, feature|
        expect(I18n.exists?("super_admin.installation_features.#{key}.name")).to be(true), key
        expect(I18n.exists?("super_admin.installation_features.#{key}.description")).to be(true), key
        expect(feature[:description]).to be_present
      end
    end
  end
end
