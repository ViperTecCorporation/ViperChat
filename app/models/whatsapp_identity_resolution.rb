class WhatsappIdentityResolution < ApplicationRecord
  belongs_to :whatsapp_message_identity
  belongs_to :partner_inbox, class_name: 'Inbox'

  validates :state, inclusion: { in: %w[pending resolved conflict review disabled] }
  validates :reason, presence: true
  scope :due, -> { where(state: 'pending').where(next_attempt_at: ..Time.current) }

  after_create_commit :enqueue_resolution

  private

  def enqueue_resolution
    Whatsapp::ResolvePendingIdentityJob.perform_later(id)
  end
end
