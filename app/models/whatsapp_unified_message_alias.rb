class WhatsappUnifiedMessageAlias < ApplicationRecord
  belongs_to :whatsapp_unified_message, optional: true
  belongs_to :message, optional: true
  belongs_to :whatsapp_message_identity

  validate :authorized_identity
  validate :message_scope
  after_commit :wake_pending_events, on: [:create, :update]

  private

  def wake_pending_events
    Whatsapp::UnifiedEventService.wake(whatsapp_message_identity)
    Whatsapp::ReconcileUnifiedMediaJob.perform_later(whatsapp_unified_message_id) if whatsapp_unified_message_id
  end

  def message_scope
    return unless message
    return if message.account_id == whatsapp_message_identity&.account_id && !message.private? && !message.web_attendance?

    errors.add(:message, 'must be public and belong to the identity account')
  end

  def authorized_identity
    link = identity_link
    identity = whatsapp_message_identity
    return errors.add(:base, 'requires an authorized canonical message') unless link && identity
    return if identity.account_id == link.account_id && link.covers?(identity.inbox)

    errors.add(:whatsapp_message_identity, 'must belong to the authorized inbox pair')
  end

  def identity_link
    whatsapp_unified_message&.whatsapp_inbox_link || WhatsappInboxLink.for_inbox(message&.inbox)
  end
end
