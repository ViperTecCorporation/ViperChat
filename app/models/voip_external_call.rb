class VoipExternalCall < ApplicationRecord
  self.filter_attributes += [:snapshot]
  belongs_to :voip_service
  belongs_to :conversation, optional: true
  belongs_to :call_message, class_name: 'Message', optional: true
  validates :source_instance_id, :provider_call_id, presence: true
  has_many :voip_calls, dependent: :nullify
  has_one :voip_call_artifact, dependent: :restrict_with_exception
end
