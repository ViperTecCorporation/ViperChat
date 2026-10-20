class Whatsapp::InboxLinkPhoneService
  # Same comparison key as MessageIdentityCorrelationService#phone. Never saves
  # the key to a channel, contact or observation, nor guesses a local country code.
  def self.normalize(value)
    number = value.to_s.delete_prefix('+')
    return unless number.match?(/\A[1-9][0-9]{6,14}\z/)
    return number unless number.match?(/\A55[0-9]{2}[6-9][0-9]{7}\z/)

    candidate = Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(number)
    parsed = Phonelib.parse("+#{candidate}")
    parsed.valid? && parsed.type == :mobile ? candidate : number
  end
end
