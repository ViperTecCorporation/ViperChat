class WhatsappUnifiedReviewAction < ApplicationRecord
  belongs_to :whatsapp_inbox_link
  belongs_to :actor, class_name: 'User', optional: true

  validates :subject_kind, inclusion: { in: %w[event delivery media reservation] }
  validates :action, inclusion: { in: %w[recheck acknowledge] }
  validates :subject_id, :subject_updated_at, presence: true
end
