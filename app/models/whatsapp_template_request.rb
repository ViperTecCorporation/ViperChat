# A creation journal: do not repeat a POST whose result may have been lost.
class WhatsappTemplateRequest < ApplicationRecord
  belongs_to :account
  belongs_to :channel, class_name: 'Channel::Whatsapp'

  validates :waba_id, :name, :language, :fingerprint, presence: true
  validates :state, inclusion: { in: %w[dispatched accepted rejected uncertain] }
  validate :matching_account

  private

  def matching_account
    errors.add(:channel, 'must belong to the account') if channel && channel.account_id != account_id
  end
end
