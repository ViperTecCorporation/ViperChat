module Channelable
  extend ActiveSupport::Concern

  CREATION_FEATURES = {
    'Channel::Api' => 'channel_api',
    'Channel::Email' => 'channel_email',
    'Channel::WebWidget' => 'channel_website',
    'Channel::FacebookPage' => 'channel_facebook',
    'Channel::Instagram' => 'channel_instagram',
    'Channel::Tiktok' => 'channel_tiktok',
    'Channel::NotificaMe' => 'channel_notifica_me',
    'Channel::Voice' => 'channel_voice'
  }.freeze

  included do
    validates :account_id, presence: true
    validate :account_allows_channel_creation, on: :create
    belongs_to :account
    has_one :inbox, as: :channel, dependent: :destroy_async, touch: true
    after_update :create_audit_log_entry
  end

  def create_audit_log_entry; end

  private

  def account_allows_channel_creation
    return unless account
    return if instance_of?(Channel::Internal)

    feature = CREATION_FEATURES[self.class.name]
    return if account.feature_enabled?('inbox_management') && (feature.nil? || account.feature_enabled?(feature))

    errors.add(:base, I18n.t('super_admin.channel_creation_blocked'))
  end
end

Channelable.prepend_mod_with('Channelable')
