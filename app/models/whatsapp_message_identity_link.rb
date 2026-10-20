class WhatsappMessageIdentityLink < ApplicationRecord
  belongs_to :whatsapp_message_identity
  belongs_to :message

  validate :matching_scope

  after_create_commit :wake_pending_contact_resolution

  private

  def wake_pending_contact_resolution
    Whatsapp::PendingIdentityResolutionService.wake(whatsapp_message_identity)
    alias_row = WhatsappUnifiedMessageAlias.find_by(whatsapp_message_identity: whatsapp_message_identity)
    Whatsapp::ReconcileUnifiedMediaJob.perform_later(alias_row.whatsapp_unified_message_id) if alias_row&.whatsapp_unified_message_id
  end

  def matching_scope
    return unless message && whatsapp_message_identity
    return if message.account_id == whatsapp_message_identity.account_id && message.inbox_id == whatsapp_message_identity.inbox_id

    errors.add(:message, 'must belong to the identity account and inbox')
  end
end
