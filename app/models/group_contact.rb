class GroupContact < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact

  validates :account_id, :conversation_id, :contact_id, presence: true
  validates :contact_id, uniqueness: { scope: :conversation_id }
  validate :conversation_must_be_group
  validate :contact_must_belong_to_account

  before_validation :set_account_id

  private

  def set_account_id
    self.account_id ||= conversation&.account_id
  end

  def conversation_must_be_group
    errors.add(:conversation, 'must be a group conversation') if conversation && !conversation.group?
  end

  def contact_must_belong_to_account
    return if contact.blank? || conversation.blank?

    errors.add(:contact, 'must belong to the same account') if contact.account_id != conversation.account_id
  end
end
