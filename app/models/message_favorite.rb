class MessageFavorite < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :message

  validates :message_id, uniqueness: { scope: :user_id }
  validate :message_belongs_to_account

  private

  def message_belongs_to_account
    errors.add(:message, :invalid) if message && (message.account_id != account_id || message.activity?)
  end
end
