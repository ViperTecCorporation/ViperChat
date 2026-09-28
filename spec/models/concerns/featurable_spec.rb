# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Featurable do
  describe 'advanced search account settings' do
    before do
      config = InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
      config.update!(value: described_class::FEATURE_LIST)
    end

    it 'enables search and indexing by default on a new account' do
      account = create(:account)

      expect(account.feature_enabled?('advanced_search')).to be true
      expect(account.feature_enabled?('advanced_search_indexing')).to be true
    end

    it 'enables search when legacy installation defaults have no search entries' do
      InstallationConfig.find_by!(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').update!(value: [{ name: 'channel_api', enabled: true }])
      account = create(:account)

      expect(account.feature_enabled?('advanced_search')).to be true
      expect(account.feature_enabled?('advanced_search_indexing')).to be true
    end

    it 'preserves an explicitly disabled installation default' do
      InstallationConfig.find_by!(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').update!(value: [{ name: 'advanced_search', enabled: false }])

      expect(create(:account).feature_enabled?('advanced_search')).to be false
    end

    it 'preserves a disabled search flag after reload and in the frontend payload' do
      account = create(:account)
      account.disable_features!('advanced_search')

      expect(account.reload.feature_enabled?('advanced_search')).to be false
      expect(account.all_features['advanced_search']).to be false
      expect(account.feature_enabled?('advanced_search_indexing')).to be true
      account.enable_features!('advanced_search')
      expect(account.reload.feature_enabled?('advanced_search')).to be true
    end

    it 'does not restore explicitly deselected flags when creating an account' do
      account = create(:account, selected_feature_flags: [])

      expect(account.reload.feature_enabled?('advanced_search')).to be false
      expect(account.feature_enabled?('advanced_search_indexing')).to be false
    end

    it 'respects a disabled indexing flag without disabling search' do
      account = create(:account)
      account.disable_features!('advanced_search_indexing')

      expect(account.reload.feature_enabled?('advanced_search_indexing')).to be false
      expect(account.feature_enabled?('advanced_search')).to be true
    end
  end

  describe '.feature_flag_mappings_for' do
    it 'maps features to the default feature_flags column when column is omitted' do
      mappings = described_class.feature_flag_mappings_for([
                                                             { 'name' => 'inbound_emails' },
                                                             { 'name' => 'ip_lookup' }
                                                           ])

      expect(mappings['feature_flags']).to eq(
        1 => :feature_inbound_emails,
        2 => :feature_ip_lookup
      )
      expect(mappings['feature_flags_ext_1']).to eq({})
    end

    it 'maps extension flags to feature_flags_ext_1 with independent bit positions' do
      mappings = described_class.feature_flag_mappings_for([
                                                             { 'name' => 'inbound_emails' },
                                                             { 'name' => 'ext_one', 'column' => 'feature_flags_ext_1' },
                                                             { 'name' => 'ext_two', 'column' => 'feature_flags_ext_1' }
                                                           ])

      expect(mappings['feature_flags']).to eq(1 => :feature_inbound_emails)
      expect(mappings['feature_flags_ext_1']).to eq(
        1 => :feature_ext_one,
        2 => :feature_ext_two
      )
    end

    it 'raises when a feature references an unknown flag column' do
      expect do
        described_class.feature_flag_mappings_for([
                                                    { 'name' => 'unknown_column_feature', 'column' => 'feature_flags_3' }
                                                  ])
      end.to raise_error(ArgumentError, /Unknown account feature flag column: feature_flags_3/)
    end

    it 'raises when a flag column has more than the supported number of features' do
      features = Array.new(64) { |index| { 'name' => "feature_#{index}" } }

      expect do
        described_class.feature_flag_mappings_for(features)
      end.to raise_error(ArgumentError, /feature_flags supports up to 63 features/)
    end
  end
end
