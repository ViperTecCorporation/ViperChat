class VoipCall < ApplicationRecord
  LIVE_STATES = %w[initiating ringing active].freeze
  TERMINAL_STATES = %w[ended unanswered missed rejected busy cancelled failed answered_elsewhere].freeze
  STATES = (LIVE_STATES + TERMINAL_STATES + ['awaiting_confirmation']).freeze
  belongs_to :account
  belongs_to :voip_agent_extension
  belongs_to :voip_external_call, optional: true
  has_many :voip_call_observations, dependent: :destroy
  before_validation :snapshot_extension, on: :create

  validates :client_call_id, presence: true, length: { maximum: 128 }, uniqueness: { scope: :voip_agent_extension_id }
  validates :remote_address, format: { with: /\A[a-zA-Z0-9_.+*#-]{1,128}\z/ }
  validates :remote_name, length: { maximum: 128 }
  validates :sip_call_id, length: { maximum: 256 }
  validates :direction, inclusion: { in: %w[incoming outgoing] }
  validates :state, inclusion: { in: STATES }
  validates :origin, inclusion: { in: %w[client_observed provider_authoritative] }
  validate :account_scope

  # Keep every SIP dialog for audit, but do not list a losing device as another
  # call when this exact external call was answered on the same agent binding.
  scope :consolidated_history, lambda {
    where(<<~SQL.squish)
      NOT (voip_calls.state = 'answered_elsewhere' AND EXISTS (
        SELECT 1 FROM voip_calls answered
        WHERE answered.voip_external_call_id = voip_calls.voip_external_call_id
          AND answered.voip_agent_extension_id = voip_calls.voip_agent_extension_id
          AND answered.direction = voip_calls.direction
          AND answered.answered_at IS NOT NULL
          AND answered.id != voip_calls.id
      ))
    SQL
  }

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
            duration: answered_at && ended_at ? [(ended_at - answered_at).to_i, 0].max : nil,
            artifacts: artifact_payload
          )
  end

  private

  def artifact_payload
    artifact = voip_external_call&.voip_call_artifact
    return unless artifact

    url = "/api/v1/accounts/#{account_id}/voip/calls/#{id}/recording" if artifact.recording.attached?
    artifact.public_payload.merge('recording_url' => url)
  end

  def snapshot_extension
    self.local_extension = voip_agent_extension.extension
    self.local_agent_id = voip_agent_extension.account_user.user_id
  end

  def account_scope
    errors.add(:account, 'does not match extension') unless account_id == voip_agent_extension.voip_service.account_id
  end
end
