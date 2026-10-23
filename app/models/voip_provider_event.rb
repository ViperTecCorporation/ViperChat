class VoipProviderEvent < ApplicationRecord
  self.filter_attributes += [:payload]
  belongs_to :voip_service
  validates :source_instance_id, :event_id, :provider_call_id, :content_digest, :payload, presence: true
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  scope :pending, -> { where(processed_at: nil) }
  scope :due, -> { pending.where('attempts < 8').where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.current) }
end
