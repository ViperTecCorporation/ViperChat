class VoipCallObservation < ApplicationRecord
  belongs_to :voip_call
  validates :event_id, presence: true, length: { maximum: 128 }, uniqueness: { scope: :voip_call_id }
  validates :sequence, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :voip_call_id }
  validates :state, inclusion: { in: VoipCall::STATES }
end
