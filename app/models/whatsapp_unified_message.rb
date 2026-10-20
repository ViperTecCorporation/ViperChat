class WhatsappUnifiedMessage < ApplicationRecord
  belongs_to :whatsapp_inbox_link
  belongs_to :message, optional: true
  has_many :aliases, class_name: 'WhatsappUnifiedMessageAlias', dependent: :delete_all
  has_many :identities, through: :aliases, source: :whatsapp_message_identity

  validates :original_id, :participant_key, :message_kind, presence: true
  validates :direction, inclusion: { in: %w[incoming outgoing] }
  validate :message_scope
  after_commit :schedule_media_reconciliation, on: [:create, :update]

  private

  def schedule_media_reconciliation
    return unless saved_change_to_message_id? && message_id && Whatsapp::UnifiedMediaReconciliationService::MEDIA_TYPES.key?(message_kind)

    Whatsapp::ReconcileUnifiedMediaJob.perform_later(id)
  end

  def message_scope
    return unless message && whatsapp_inbox_link
    return if message.account_id == whatsapp_inbox_link.account_id && message.inbox_id == whatsapp_inbox_link.primary_inbox_id && !message.private?

    errors.add(:message, 'must be a public message in the primary inbox')
  end
end
