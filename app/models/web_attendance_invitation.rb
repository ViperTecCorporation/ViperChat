class WebAttendanceInvitation < ApplicationRecord
  belongs_to :conversation
  belongs_to :message, optional: true
  belongs_to :account
  belongs_to :inbox
  belongs_to :contact
  has_many :web_attendance_sessions, dependent: :destroy
  before_validation :bind_identity, on: :create

  validates :token_digest, presence: true, uniqueness: true
  validates :cycle, presence: true

  def self.encryptor
    key = Rails.application.key_generator.generate_key('web-attendance-invitations', 32)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def link
    token = self.class.encryptor.decrypt_and_verify(encrypted_token)
    "#{ENV.fetch('FRONTEND_URL')}/web-attendance#token=#{token}"
  end

  def active?
    activated_at.present? && available?
  end

  def available?
    revoked_at.nil? && current_identity? && !conversation.resolved? && !conversation.group? && conversation.inbox.web_attendance_available?
  end

  def activate!
    conversation.with_lock do
      next unless available?

      if newer_active_invitation?
        update!(revoked_at: Time.current)
        next
      end

      update!(activated_at: Time.current) unless activated_at?
      conversation.web_attendance_invitations.where('id < ?', id).where(revoked_at: nil).find_each do |invite|
        invite.update!(revoked_at: Time.current)
      end
    end
  end

  private

  def current_identity?
    cycle == conversation.web_attendance_cycle && account_id == conversation.account_id &&
      inbox_id == conversation.inbox_id && contact_id == conversation.contact_id
  end

  def newer_active_invitation?
    conversation.web_attendance_invitations.where('id > ?', id).where.not(activated_at: nil).exists?(revoked_at: nil)
  end

  def bind_identity
    self.account = conversation.account
    self.inbox = conversation.inbox
    self.contact = conversation.contact
  end
end
