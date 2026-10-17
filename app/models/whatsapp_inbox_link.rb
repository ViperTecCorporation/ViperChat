class WhatsappInboxLink < ApplicationRecord
  PROVIDERS = %w[unoapi whatsapp_cloud].freeze

  belongs_to :account
  belongs_to :primary_inbox, class_name: 'Inbox'
  belongs_to :secondary_inbox, class_name: 'Inbox'

  scope :active, -> { where(enabled: true).where.not(activated_at: nil) }
  scope :covering, ->(inbox_id) { where(primary_inbox_id: inbox_id).or(where(secondary_inbox_id: inbox_id)) }

  validates :default_provider, inclusion: { in: PROVIDERS }
  validates :enabled, inclusion: { in: [true, false] }
  validate :valid_pair
  validate :exclusive_active_pair
  validate :immutable_active_pair
  around_save :save_under_account_lock

  def self.for_inbox(inbox)
    return unless inbox

    active.where(account_id: inbox.account_id).covering(inbox.id).first
  end

  def covers?(inbox)
    inbox.account_id == account_id && [primary_inbox_id, secondary_inbox_id].include?(inbox.id)
  end

  def inbox_for(provider)
    [primary_inbox, secondary_inbox].find { |inbox| inbox.whatsapp? && inbox.channel.provider == provider }
  end

  def partner_for(inbox)
    return unless covers?(inbox)

    inbox.id == primary_inbox_id ? secondary_inbox : primary_inbox
  end

  def transport_options(conversation)
    Whatsapp::InboxLinkTransportOptionsService.new(link: self, conversation: conversation).perform
  end

  private

  # The account lock serializes cross-column overlap checks, not just same-column indexes.
  # Validate again inside it so direct model saves also obey the one-active-pair rule.
  def save_under_account_lock
    account.with_lock do
      raise ActiveRecord::RecordInvalid, self unless valid?

      self.activated_at = Time.current if enabled? && (!enabled_in_database || activated_at.nil?)
      yield
    end
  end

  def valid_pair
    return unless primary_inbox && secondary_inbox

    pair = [primary_inbox, secondary_inbox]
    validate_pair_account(pair)
    unless valid_pair_providers?(pair)
      errors.add(:base, 'Pair requires one UnoAPI inbox and one WhatsApp Cloud inbox')
      return
    end

    validate_pair_phones(pair)
  end

  def validate_pair_account(pair)
    errors.add(:base, 'Inboxes must be distinct and belong to the same account') unless
      primary_inbox_id != secondary_inbox_id && pair.all? { |inbox| inbox.account_id == account_id }
  end

  def valid_pair_providers?(pair)
    pair.all?(&:whatsapp?) && pair.map { |inbox| inbox.channel.provider }.sort == PROVIDERS.sort
  end

  def validate_pair_phones(pair)
    phones = pair.map { |inbox| Whatsapp::InboxLinkPhoneService.normalize(inbox.channel.phone_number) }
    errors.add(:base, 'Business phone numbers must match') unless phones.all?(&:present?) && phones.uniq.one?
  end

  def exclusive_active_pair
    return unless enabled?

    ids = [primary_inbox_id, secondary_inbox_id].compact
    overlaps = self.class.where(account_id: account_id, enabled: true).where.not(id: id)
    return unless overlaps.where(primary_inbox_id: ids).or(overlaps.where(secondary_inbox_id: ids)).exists?

    errors.add(:base, 'An inbox already belongs to an enabled pair')
  end

  def immutable_active_pair
    return unless persisted? && enabled_in_database
    return unless will_save_change_to_primary_inbox_id? || will_save_change_to_secondary_inbox_id? || will_save_change_to_account_id?

    errors.add(:base, 'Disable the existing pair before changing its inboxes')
  end
end
