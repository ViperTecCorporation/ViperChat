require 'rails_helper'

RSpec.describe Whatsapp::InboxLinkPhoneService do
  it 'compares legacy BR mobiles using only a validated mobile ninth-digit candidate' do
    expect(described_class.normalize('+556696222471')).to eq('5566996222471')
    expect(described_class.normalize('5566996222471')).to eq('5566996222471')
  end

  it 'preserves international digit-only numbers without guessing a country code' do
    expect(described_class.normalize('+14155552671')).to eq('14155552671')
    expect(described_class.normalize('14155552671')).to eq('14155552671')
  end

  it 'preserves landlines and invalid DDD numbers rather than expanding them' do
    expect(described_class.normalize('551132222471')).to eq('551132222471')
    expect(described_class.normalize('550096222471')).to eq('550096222471')
  end

  it 'does not use an unvalidated or non-mobile BR candidate' do
    parsed = instance_double(Phonelib::Phone, valid?: false, type: :mobile)
    allow(Phonelib).to receive(:parse).with('+5566996222471').and_return(parsed)
    expect(described_class.normalize('556696222471')).to eq('556696222471')
    allow(parsed).to receive_messages(valid?: true, type: :fixed_line)
    expect(described_class.normalize('556696222471')).to eq('556696222471')
  end

  it 'rejects noninternational formatting, technical identifiers and missing values' do
    [nil, '', '+55 (66) 99622-2471', '005566996222471', '5566996222471@g.us', 'bsuid-value', '123456', '1234567890123456'].each do |value|
      expect(described_class.normalize(value)).to be_nil
    end
  end
end
