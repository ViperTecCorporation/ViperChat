class VoipAgentExtension < ApplicationRecord
  include VoipCredentials
  belongs_to :account_user, optional: true
  belongs_to :voip_service
  has_many :voip_calls, dependent: :restrict_with_error

  validates :extension, :auth_username, format: { with: /\A[a-zA-Z0-9_.+*-]{1,64}\z/ }
  validates :account_user_id, uniqueness: { scope: :voip_service_id }, allow_nil: true
  validates :extension, uniqueness: { scope: :voip_service_id, conditions: -> { where.not(account_user_id: nil) } },
                        if: -> { account_user_id.present? }
  validate :same_account

  def public_payload
    slice(:id, :voip_service_id, :extension, :auth_username, :active, :updated_at).merge(
      credential_configured: credentials['password'].present?, service_name: voip_service.name
    )
  end

  def self.busy?(membership)
    VoipCall.joins(:voip_agent_extension).where(voip_agent_extensions: { account_user_id: membership.id })
            .where(state: VoipCall::LIVE_STATES).exists?(['last_observed_at > ?', 90.seconds.ago])
  end

  private

  def same_account
    return unless account_user

    errors.add(:voip_service, 'must belong to this account') unless account_user.account_id == voip_service.account_id
  end
end
