module VoipCredentials
  extend ActiveSupport::Concern

  def credentials
    return {} if encrypted_credentials.blank?

    JSON.parse(credential_cipher.decrypt_and_verify(encrypted_credentials, purpose: 'agent-voip'))
  end

  def credentials=(value)
    self.encrypted_credentials = credential_cipher.encrypt_and_sign(value.to_json, purpose: 'agent-voip')
  end

  private

  def credential_cipher
    key = Rails.application.key_generator.generate_key('viperchat-agent-voip-v1', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
  end
end
