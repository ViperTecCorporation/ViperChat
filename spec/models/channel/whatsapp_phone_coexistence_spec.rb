require 'rails_helper'

RSpec.describe Channel::Whatsapp do
  let(:account) { create(:account) }
  let(:phone) { '+5581988985300' }

  %w[unoapi whatsapp_cloud].each do |first_provider|
    it "allows the same exact number across Meta/ViperConnect when #{first_provider} exists first" do
      original = create(:channel_whatsapp, account: account, phone_number: phone, provider: first_provider,
                                           sync_templates: false, validate_provider_config: false)
      second_provider = first_provider == 'unoapi' ? 'whatsapp_cloud' : 'unoapi'
      partner = create(:channel_whatsapp, account: account, phone_number: phone, provider: second_provider,
                                          sync_templates: false, validate_provider_config: false)

      expect(original.reload.phone_number).to eq(phone)
      expect(partner.reload.phone_number).to eq(phone)
      expect(partner.id).not_to eq(original.id)
      expect(original.inbox).not_to eq(partner.inbox)
    end

    it "blocks a second #{first_provider} with either Brazilian representation" do
      create(:channel_whatsapp, account: account, phone_number: phone, provider: first_provider,
                                sync_templates: false, validate_provider_config: false)
      duplicate = build(:channel_whatsapp, account: account, phone_number: '+558188985300', provider: first_provider)
      allow(duplicate).to receive(:validate_provider_config)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:phone_number]).to include(I18n.t('errors.messages.taken'))
    end
  end

  it 'does not allow another account to claim the partner number' do
    create(:channel_whatsapp, account: account, phone_number: phone, provider: 'unoapi',
                              sync_templates: false, validate_provider_config: false)
    partner = build(:channel_whatsapp, account: create(:account), phone_number: '+55 (81) 98898-5300', provider: 'whatsapp_cloud')
    allow(partner).to receive(:validate_provider_config)
    expect(partner).not_to be_valid
    expect(partner.errors[:phone_number]).not_to be_empty
  end

  it 'preserves the phone representations when the partner uses eight digits' do
    original = create(:channel_whatsapp, account: account, phone_number: '+558188985300', provider: 'whatsapp_cloud',
                                         sync_templates: false, validate_provider_config: false)
    partner = create(:channel_whatsapp, account: account, phone_number: phone, provider: 'unoapi',
                                        sync_templates: false, validate_provider_config: false)
    expect(original.reload.phone_number).to eq('+558188985300')
    expect(partner.reload.phone_number).to eq(phone)
  end

  it 'does not treat 360dialog as an additional coexistence transport' do
    create(:channel_whatsapp, account: account, phone_number: phone, provider: 'default',
                              sync_templates: false, validate_provider_config: false)
    duplicate = build(:channel_whatsapp, account: account, phone_number: phone, provider: 'whatsapp_cloud')
    allow(duplicate).to receive(:validate_provider_config)
    expect(duplicate).not_to be_valid
    duplicate.provider = 'unoapi'
    expect(duplicate).not_to be_valid
  end

  it 'retains database protection against two ViperConnect channels with the same exact phone' do
    original = create(:channel_whatsapp, account: account, phone_number: phone, provider: 'unoapi',
                                         sync_templates: false, validate_provider_config: false)
    other = create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
    expect do
      # Deliberately bypass the model to verify the database uniqueness constraint.
      described_class.transaction(requires_new: true) { other.update_columns(phone_number: original.phone_number) } # rubocop:disable Rails/SkipsModelValidations
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
