class WhatsappMessageIdentity < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :channel, class_name: 'Channel::Whatsapp'
  has_many :message_links, class_name: 'WhatsappMessageIdentityLink', dependent: :delete_all
  has_many :messages, through: :message_links

  validates :external_id, :provider, presence: true
  validate :matching_scope

  def link_matching_messages
    inbox.messages.where(account_id: account_id, source_id: external_id).find_each do |message|
      message_links.create_or_find_by!(message: message)
    end
  end

  private

  def matching_scope
    return unless inbox && channel
    return if inbox.account_id == account_id && inbox.channel_id == channel_id && inbox.whatsapp? && channel.provider == provider

    errors.add(:inbox, 'must belong to the identity account and channel')
  end
end
