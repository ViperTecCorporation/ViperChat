class Whatsapp::ChannelPhoneIdentity
  def self.comparison_key(phone_number)
    digits = phone_number.to_s.gsub(/\D/, '')
    Whatsapp::InboxLinkPhoneService.normalize(digits) || digits
  end

  def self.channels(phone_number)
    digits = phone_number.to_s.gsub(/\D/, '')
    canonical = Whatsapp::InboxLinkPhoneService.normalize(digits)
    numbers = [digits, canonical].compact_blank
    if canonical&.match?(/\A55\d{2}9\d{8}\z/)
      short = canonical.sub(/\A(55\d{2})9/, '\1')
      numbers << short if Whatsapp::InboxLinkPhoneService.normalize(short) == canonical
    end
    Channel::Whatsapp.where("regexp_replace(phone_number, '[^0-9]', '', 'g') IN (?)", numbers.uniq)
  end

  def self.conflict(phone_number:, provider:, account_id:, except_id: nil)
    channels(phone_number).where.not(id: except_id).detect do |channel|
      channel.account_id != account_id || [channel.provider, provider].compact.sort != %w[unoapi whatsapp_cloud]
    end
  end
end
