# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number  (phone_number) UNIQUE
#

class Channel::Whatsapp < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [:phone_number, :provider, { provider_config: {} }].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud unoapi].freeze
  before_validation :ensure_unoapi_group_conversation_schema_default
  before_validation :ensure_webhook_verify_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  after_create :sync_templates
  before_destroy :teardown_webhooks
  after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?
  after_update_commit :enqueue_group_conversation_backfill, if: :should_backfill_group_conversations?

  def name
    'Whatsapp'
  end

  def provider_service
    if provider == 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    elsif provider == 'unoapi'
      Whatsapp::Providers::UnoapiService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  def messaging_window_enabled?
    provider_config['url'] == 'https://graph.facebook.com'
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :send_reaction, to: :provider_service
  delegate :send_message_edit, to: :provider_service
  delegate :send_message_update, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service
  delegate :message_path, to: :provider_service
  delegate :message_update_payload, to: :provider_service
  delegate :message_update_http_method, to: :provider_service

  def setup_webhooks
    perform_webhook_setup
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    prompt_reauthorization!
  end

  private

  def ensure_webhook_verify_token
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if %w[whatsapp_cloud unoapi].include?(provider)
  end

  def ensure_unoapi_group_conversation_schema_default
    return unless provider == 'unoapi'

    self.provider_config ||= {}
    provider_config['use_group_conversation_schema'] = true unless provider_config.key?('use_group_conversation_schema')
  end

  def validate_provider_config
    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  rescue HTTParty::Error => e
    errors.add(:provider_config, e.message)
  rescue SocketError, Errno::ECONNREFUSED
    errors.add(:provider_config, 'Conection refused, verify Whatsapp Cloud API URL field')
  end

  def perform_webhook_setup
    business_account_id = provider_config['business_account_id']
    api_key = provider_config['api_key']

    Whatsapp::WebhookSetupService.new(self, business_account_id, api_key).perform
  end

  def teardown_webhooks
    Whatsapp::WebhookTeardownService.new(self).perform
  end

  def should_auto_setup_webhooks?
    # Only auto-setup webhooks for whatsapp_cloud provider with manual setup
    # Embedded signup calls setup_webhooks explicitly in EmbeddedSignupService
    provider == 'whatsapp_cloud' && provider_config['source'] != 'embedded_signup'
  end

  def should_backfill_group_conversations?
    return false unless provider == 'unoapi'
    return false unless saved_change_to_provider_config?

    old_config, new_config = saved_change_to_provider_config
    old_value = ActiveModel::Type::Boolean.new.cast(old_config&.dig('use_group_conversation_schema'))
    new_value = ActiveModel::Type::Boolean.new.cast(new_config&.dig('use_group_conversation_schema'))

    !old_value && new_value
  end

  def enqueue_group_conversation_backfill
    return if inbox.blank?

    Whatsapp::GroupConversationBackfillJob.perform_later(inbox.id)
    Rails.logger.info("[WHATSAPP][GROUP] backfill enqueued inbox_id=#{inbox.id}")
  end
end
