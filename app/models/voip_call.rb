class VoipCall < ApplicationRecord
  LIVE_STATES = %w[initiating ringing active].freeze
  TERMINAL_STATES = %w[ended unanswered missed rejected busy cancelled failed answered_elsewhere].freeze
  STATES = (LIVE_STATES + TERMINAL_STATES + ['awaiting_confirmation']).freeze
  belongs_to :account
  belongs_to :voip_agent_extension
  has_many :voip_call_observations, dependent: :destroy
  before_validation :snapshot_extension, on: :create

  validates :client_call_id, presence: true, length: { maximum: 128 }, uniqueness: { scope: :voip_agent_extension_id }
  validates :remote_address, format: { with: /\A[a-zA-Z0-9_.+*#-]{1,128}\z/ }
  validates :remote_name, length: { maximum: 128 }
  validates :sip_call_id, length: { maximum: 256 }
  validates :direction, inclusion: { in: %w[incoming outgoing] }
  validates :state, inclusion: { in: STATES }
  validates :origin, inclusion: { in: ['client_observed'] }
  validate :account_scope

  def identity_address
    return remote_address unless direction == 'outgoing'

    evidence = voip_call_observations.select do |row|
      row.sequence <= last_sequence && row.details['resolved_address'].to_s.match?(/\A\+?\d{10,15}\z/)
    end.max_by(&:sequence)
    evidence ? evidence.details.fetch('resolved_address') : remote_address
  end

  def public_payload(remote_identity: nil)
    effective = LIVE_STATES.include?(state) && last_observed_at < 90.seconds.ago ? 'awaiting_confirmation' : state
    slice(:id, :client_call_id, :sip_call_id, :direction, :remote_address, :remote_name, :origin, :started_at,
          :answered_at, :ended_at, :sip_code, :end_reason).merge(
            state: effective, service_id: voip_agent_extension.voip_service_id, service_name: voip_agent_extension.voip_service.name,
            agent_id: local_agent_id, extension: local_extension, remote_identity: remote_identity,
            duration: answered_at && ended_at ? [(ended_at - answered_at).to_i, 0].max : nil
          )
  end

  private

  def snapshot_extension
    self.local_extension = voip_agent_extension.extension
    self.local_agent_id = voip_agent_extension.account_user.user_id
  end

  def account_scope
    errors.add(:account, 'does not match extension') unless account_id == voip_agent_extension.voip_service.account_id
  end
end
