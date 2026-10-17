class WhatsappUnifiedEvent < ApplicationRecord
  belongs_to :whatsapp_inbox_link
  belongs_to :whatsapp_message_identity

  validates :state, inclusion: { in: %w[pending completed review disabled] }
  validates :reason, :activation_cutoff, presence: true
  validate :matching_scope

  private

  def matching_scope
    link = whatsapp_inbox_link
    identity = whatsapp_message_identity
    return if link && identity && link.account_id == identity.account_id && link.covers?(identity.inbox)

    errors.add(:whatsapp_message_identity, 'must belong to the authorized inbox pair')
  end
end
