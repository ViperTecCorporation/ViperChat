require 'rails_helper'

describe ConfigLoader do
  subject(:trigger) { described_class.new.process }

  describe 'execute' do
    context 'when called with default options' do
      it 'creates installation configs' do
        expect(InstallationConfig.count).to eq(0)
        subject
        expect(InstallationConfig.count).to be > 0
      end

      it 'creates account level feature defaults as entry on config table' do
        subject
        expect(InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')).to be_truthy
      end
    end

    context 'with reconcile_only_new option' do
      let(:class_instance) { described_class.new }
      let(:config) { { name: 'WHO', value: 'corona' } }
      let(:updated_config) { { name: 'WHO', value: 'covid 19' } }

      before do
        allow(described_class).to receive(:new).and_return(class_instance)
        allow(class_instance).to receive(:general_configs).and_return([config])
        described_class.new.process
      end

      it 'being true it should not update existing config value' do
        expect(InstallationConfig.find_by(name: 'WHO').value).to eq('corona')
        allow(class_instance).to receive(:general_configs).and_return([updated_config])
        described_class.new.process({ reconcile_only_new: true })
        expect(InstallationConfig.find_by(name: 'WHO').value).to eq('corona')
      end

      it 'updates the existing config value with new default value' do
        expect(InstallationConfig.find_by(name: 'WHO').value).to eq('corona')
        allow(class_instance).to receive(:general_configs).and_return([updated_config])
        described_class.new.process({ reconcile_only_new: false })
        expect(InstallationConfig.find_by(name: 'WHO').value).to eq('covid 19')
      end
    end

    context 'with account feature defaults' do
      let(:class_instance) { described_class.new }
      let(:account_features) do
        [
          { 'name' => 'inbox_management', 'enabled' => true },
          { 'name' => 'channel_website', 'enabled' => true }
        ]
      end

      before do
        allow(described_class).to receive(:new).and_return(class_instance)
        allow(class_instance).to receive(:general_configs).and_return([])
        allow(class_instance).to receive(:account_features).and_return(account_features)
      end

      it 'removes stale feature flags while preserving existing feature values' do
        InstallationConfig.create!(
          name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS',
          value: [
            { 'name' => 'channel_twitter', 'enabled' => true },
            { 'name' => 'inbox_management', 'enabled' => false }
          ]
        )

        described_class.new.process({ reconcile_only_new: true })

        feature_defaults = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').value
        expect(feature_defaults.pluck('name')).to contain_exactly('inbox_management', 'channel_website')
        expect(feature_defaults.find { |feature| feature['name'] == 'inbox_management' }['enabled']).to be(false)
      end
    end
  end
end
