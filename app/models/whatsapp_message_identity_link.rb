class WhatsappMessageIdentityLink < ApplicationRecord
  belongs_to :whatsapp_message_identity
  belongs_to :message

  validate :matching_scope

  private

  def matching_scope
    return unless message && whatsapp_message_identity
    return if message.account_id == whatsapp_message_identity.account_id && message.inbox_id == whatsapp_message_identity.inbox_id

    errors.add(:message, 'must belong to the identity account and inbox')
  end
end
