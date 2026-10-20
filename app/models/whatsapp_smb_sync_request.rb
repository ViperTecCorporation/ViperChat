# A durable one-shot journal, not a claim that the asynchronous import completed.
class WhatsappSmbSyncRequest < ApplicationRecord
  belongs_to :account
  belongs_to :channel, class_name: 'Channel::Whatsapp'

  TYPES = %w[smb_app_state_sync history].freeze
  validates :sync_type, inclusion: { in: TYPES }
  validates :state, inclusion: { in: %w[prepared dispatched accepted rejected uncertain] }
  validates :phone_number_id, :waba_id, presence: true
  validates :history_max_age_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 3650 }
  validate :matching_account

  def summary
    attributes.slice('sync_type', 'state', 'request_id', 'reason', 'history_max_age_days', 'dispatched_at', 'updated_at')
  end

  private

  def matching_account
    errors.add(:channel, 'must belong to the account') if channel && channel.account_id != account_id
  end
end
