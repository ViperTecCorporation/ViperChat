class VoipFavorite < ApplicationRecord
  belongs_to :account_user
  belongs_to :voip_service
  validates :name, presence: true, length: { maximum: 128 }
  validates :address, format: { with: /\A[a-zA-Z0-9_.+*#-]{1,128}\z/ }, uniqueness: { scope: [:account_user_id, :voip_service_id] }
  validate :same_account

  private

  def same_account
    errors.add(:voip_service, 'must belong to this account') unless account_user.account_id == voip_service.account_id
  end
end
