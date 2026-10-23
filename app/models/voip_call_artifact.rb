class VoipCallArtifact < ApplicationRecord
  self.filter_attributes += [:snapshot]
  belongs_to :voip_external_call
  belongs_to :message, optional: true
  belongs_to :conversation, optional: true
  has_one_attached :recording
  scope :due, -> { where.not(state: %w[complete failed]).where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.current) }

  def public_payload
    snapshot.slice('recording', 'ai').merge(
      'publication_state' => state,
      'conversation_id' => conversation&.display_id,
      'message_id' => message_id,
      'recording_available' => recording.attached?
    )
  end
end
