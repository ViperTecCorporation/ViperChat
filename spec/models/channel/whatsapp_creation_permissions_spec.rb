require 'rails_helper'

RSpec.describe Channel::Whatsapp do
  let(:account) { create(:account) }

  %w[default whatsapp_cloud unoapi].product([true, false], [true, false]).each do |provider, official_enabled, uno_blocked|
    it "validates #{provider} with official=#{official_enabled} and uno_blocked=#{uno_blocked}" do
      official_enabled ? account.enable_features!('channel_whatsapp') : account.disable_features!('channel_whatsapp')
      uno_blocked ? account.enable_features!('disable_channel_unoapi') : account.disable_features!('disable_channel_unoapi')
      channel = build(:channel_whatsapp, account: account, provider: provider, validate_provider_config: false)
      allow(channel).to receive(:validate_provider_config)
      allowed = provider == 'unoapi' ? !uno_blocked : official_enabled

      expect(channel.valid?).to eq(allowed)
      expect(channel.errors[:base]).to include(I18n.t('super_admin.channel_creation_blocked')) unless allowed
    end
  end

  %w[default whatsapp_cloud unoapi].each do |provider|
    it "keeps an existing #{provider} channel editable after creation is restricted" do
      channel = create(:channel_whatsapp, account: account, provider: provider, validate_provider_config: false, sync_templates: false)
      account.disable_features!('channel_whatsapp')
      account.enable_features!('disable_channel_unoapi')

      expect(channel.update(provider_config: channel.provider_config.merge('test_setting' => 'updated'))).to be(true)
    end
  end

  it 'blocks disallowed creation before contacting the external provider' do
    account.disable_features!('channel_whatsapp')
    channel = build(:channel_whatsapp, account: account, provider: 'whatsapp_cloud')
    expect(channel).not_to receive(:provider_service)

    expect(channel.save).to be(false)
  end

  it 'does not apply one account restriction to another account' do
    account.enable_features!('disable_channel_unoapi')
    channel = build(:channel_whatsapp, account: create(:account), provider: 'unoapi', validate_provider_config: false)
    allow(channel).to receive(:validate_provider_config)

    expect(channel).to be_valid
  end

  it 'blocks Twilio WhatsApp but preserves SMS creation' do
    account.disable_features!('channel_whatsapp')
    channel = build(:channel_twilio_sms, account: account, medium: :whatsapp)
    expect(channel).not_to be_valid
    expect(channel.errors[:base]).to include(I18n.t('super_admin.channel_creation_blocked'))

    channel.medium = :sms
    expect(channel).to be_valid
  end
end
