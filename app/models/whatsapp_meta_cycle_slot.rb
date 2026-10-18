# Keep the reservation if a message is removed locally: deletion must not refill a cycle.
class WhatsappMetaCycleSlot < ApplicationRecord
  belongs_to :account
  belongs_to :whatsapp_inbox_link
  belongs_to :conversation
  belongs_to :message, optional: true

  validates :cycle, :position, numericality: { only_integer: true, greater_than: 0 }
  validates :activation_cutoff, presence: true
  validate :matching_scope

  private

  def matching_scope
    scoped = whatsapp_inbox_link && conversation &&
             [whatsapp_inbox_link.account_id, conversation.account_id].all?(account_id) &&
             whatsapp_inbox_link.covers?(conversation.inbox) && matching_message?
    errors.add(:base, 'Initial Meta reservation scope mismatch') unless scoped
  end

  def matching_message?
    message.nil? || (message.account_id == account_id && message.conversation_id == conversation_id)
  end
end
