module Api::V1::Accounts::Concerns::WhatsappHealthManagement
  extend ActiveSupport::Concern

  included do
    skip_before_action :check_authorization, only: [:health, :register_webhook, :insights, :management_events, :coexistence_settings]
    before_action :check_admin_authorization?, only: [:register_webhook, :insights, :management_events, :coexistence_settings]
    before_action :validate_whatsapp_cloud_channel, only: [:health, :register_webhook, :insights, :management_events, :coexistence_settings]
  end

  def sync_templates
    return render status: :unprocessable_entity, json: { error: 'Template sync is only available for WhatsApp channels' } unless whatsapp_channel?

    trigger_template_sync
    render status: :ok, json: { message: 'Template sync initiated successfully' }
  rescue StandardError => e
    render status: :internal_server_error, json: { error: e.message }
  end

  def health
    health_data = Whatsapp::HealthService.new(@inbox.channel).fetch_health_status
    render json: health_data
  rescue StandardError => e
    Rails.logger.error "[INBOX HEALTH] Error fetching health data: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def insights
    render json: Whatsapp::AccountInsightsService.new(channel: @inbox.channel, days: params[:days].presence || 30).perform
  rescue ArgumentError
    render json: { error: 'Unsupported insights period' }, status: :unprocessable_entity
  end

  def management_events
    channel = @inbox.channel
    events = WhatsappManagementEvent.where(account_id: @inbox.account_id, channel_id: channel.id).order(created_at: :desc).limit(25)
    render json: { graph_version: Whatsapp::ApiVersion.current, session_info_version: '3',
                   supported_fields: Whatsapp::WebhookFields::ALL, events: events.map(&:summary),
                   history_settings: history_settings(channel), initial_history_sync: initial_history_sync(channel) }
  end

  def coexistence_settings
    preferences = coexistence_preferences
    channel = @inbox.channel
    channel.with_lock do
      # Keep credential callbacks out of preference changes. Initial synchronization
      # is asynchronous, explicitly gated and checks coexistence before any POST.
      channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
        provider_config: channel.provider_config.merge(preferences),
        updated_at: Time.current
      )
    end
    Whatsapp::RequestSmbAppDataJob.perform_later(channel.id) if preferences['ignore_history_messages'] == false
    render json: { history_settings: history_settings(channel), initial_history_sync: initial_history_sync(channel) }
  rescue ArgumentError
    render json: { error: 'Invalid coexistence history settings' }, status: :unprocessable_entity
  end

  def register_webhook
    Whatsapp::WebhookSetupService.new(@inbox.channel).register_callback

    render json: { message: 'Webhook registered successfully' }, status: :ok
  rescue StandardError => e
    Rails.logger.error "[INBOX WEBHOOK] Webhook registration failed: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def initial_history_sync(channel)
    { enabled: ENV['WHATSAPP_SMB_SYNC_ENABLED'] == 'true',
      requests: WhatsappSmbSyncRequest.where(account_id: @inbox.account_id, channel_id: channel.id).order(:id).map(&:summary) }
  end

  def coexistence_preferences
    days = Integer(params[:history_max_age_days].to_s, 10)
    ignored = params[:ignore_history_messages]
    raise ArgumentError unless days.between?(1, 3650) && [true, false].include?(ignored)
    raise ArgumentError if params.key?(:ignore_group_messages) && [true, false].exclude?(params[:ignore_group_messages])

    preferences = { 'ignore_history_messages' => ignored, 'history_max_age_days' => days }
    preferences['ignore_group_messages'] = params[:ignore_group_messages] if params.key?(:ignore_group_messages)
    preferences
  end

  def history_settings(channel)
    config = channel.provider_config
    { ignore_history_messages: config.fetch('ignore_history_messages', true), history_max_age_days: config.fetch('history_max_age_days', 7),
      ignore_group_messages: config.fetch('ignore_group_messages', false) }
  end

  def validate_whatsapp_cloud_channel
    return if @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.provider == 'whatsapp_cloud'

    render json: { error: 'Health data only available for WhatsApp Cloud API channels' }, status: :bad_request
  end

  def whatsapp_channel?
    @inbox.whatsapp? || (@inbox.twilio? && @inbox.channel.whatsapp?)
  end

  def trigger_template_sync
    if @inbox.whatsapp?
      Channels::Whatsapp::TemplatesSyncJob.perform_later(@inbox.channel)
    elsif @inbox.twilio? && @inbox.channel.whatsapp?
      Channels::Twilio::TemplatesSyncJob.perform_later(@inbox.channel)
    end
  end
end
