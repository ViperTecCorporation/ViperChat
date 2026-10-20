require 'base64'

# Observed coexistence envelope, not a documented Meta wire-format contract.
# Unknown versions are deliberately left uncorrelated. Never use this ID to send.
class Whatsapp::MetaMessageIdAdapter
  VERSION = 'coexistence-envelope-v2'.freeze
  PHONE_ENVELOPE = /\A\x1c\x18([\x07-\x0f])([1-9][0-9]{6,14})\x15\x02\x00([\x11\x12])\x18([\x10-\x40])([A-F0-9]{16,64})\x00\z/n
  BSUID_ENVELOPE = /\A\x1c\x18([\x0b-\x23])([A-Z]{2}\.[0-9]{8,32})\x15\x14\x00([\x11\x12])\x18([\x10-\x40])([A-F0-9]{16,64})\x00\z/n

  def self.parse(external_id)
    return unless external_id.is_a?(String) && external_id.start_with?('wamid.') && external_id.bytesize <= 512

    bytes = decode(external_id.delete_prefix('wamid.'))
    match = match_envelope(bytes) if bytes
    return unless valid_lengths?(match)

    parsed_identity(match)
  end

  def self.parsed_identity(match)
    { 'provider_message_id' => match[5], 'participant' => match[2], 'version' => VERSION,
      'participant_type' => match[2].include?('.') ? 'bsuid' : 'phone',
      'direction' => match[3].ord == 0x11 ? 'outgoing' : 'incoming' }
  end

  def self.match_envelope(bytes)
    PHONE_ENVELOPE.match(bytes) || BSUID_ENVELOPE.match(bytes)
  end

  def self.valid_lengths?(match)
    match && match[1].ord == match[2].bytesize && match[4].ord == match[5].bytesize
  end

  def self.decode(encoded)
    return unless encoded.match?(%r{\A[A-Za-z0-9+/]+={0,2}\z}) && encoded.length % 4 != 1

    bytes = Base64.strict_decode64(encoded.ljust((encoded.length + 3) / 4 * 4, '='))
    return unless Base64.strict_encode64(bytes).delete_suffix('==').delete_suffix('=') == encoded.delete_suffix('==').delete_suffix('=')

    bytes
  rescue ArgumentError
    nil
  end
  private_class_method :decode, :valid_lengths?, :match_envelope, :parsed_identity
end
