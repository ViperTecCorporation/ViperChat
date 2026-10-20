require 'rails_helper'

RSpec.describe RegexHelper do
  %W[BR.1234567890123456 IN.ENT.9081726354 user.#{'a' * 64}].each do |identifier|
    it 'accepts a supported opaque WhatsApp identity without treating it as a phone' do
      expect(described_class::WHATSAPP_BSUID_REGEX.match?(identifier)).to be(true)
      expect(described_class::WHATSAPP_CHANNEL_REGEX.match?(identifier)).to be(true)
      expect(Whatsapp::InboxLinkPhoneService.normalize(identifier)).to be_nil
    end
  end

  %W[@username user.name user.#{'a' * 63} user.#{'a' * 65} user.#{'z' * 64}].each do |identifier|
    it 'rejects usernames and unsupported opaque identity shapes' do
      expect(described_class::WHATSAPP_BSUID_REGEX.match?(identifier)).to be(false)
      expect(described_class::WHATSAPP_CHANNEL_REGEX.match?(identifier)).to be(false)
    end
  end

  it 'preserves phone and Twilio validation contracts' do
    expect(described_class::WHATSAPP_CHANNEL_REGEX.match?('5566996269251')).to be(true)
    expect(described_class::TWILIO_CHANNEL_WHATSAPP_REGEX.match?('whatsapp:+5566996269251')).to be(true)
    expect(described_class::TWILIO_CHANNEL_WHATSAPP_REGEX.match?('whatsapp:BR.1234567890123456')).to be(true)
    expect(described_class::TWILIO_CHANNEL_WHATSAPP_REGEX.match?("whatsapp:user.#{'a' * 64}")).to be(false)
  end
end
