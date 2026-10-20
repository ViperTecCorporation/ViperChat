class SuperAdmin::AppConfigsController < SuperAdmin::ApplicationController
  OPENROUTER_MODEL_FEATURES = { 'CAPTAIN_OPEN_AI_MODEL' => 'assistant', 'CAPTAIN_AUDIO_TRANSCRIPTION_MODEL' => 'audio_transcription' }.freeze
  GOOGLE_CONFIGS = %w[
    GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET GOOGLE_OAUTH_REDIRECT_URI ENABLE_GOOGLE_OAUTH_LOGIN
    GOOGLE_GMAIL_API_ENABLED GOOGLE_MAPS_API_KEY
  ].freeze
  INSTAGRAM_CONFIGS = %w[
    INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET INSTAGRAM_WEBHOOK_APP_SECRET INSTAGRAM_VERIFY_TOKEN INSTAGRAM_API_VERSION
    ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT ENABLE_INSTAGRAM_WEBHOOK_SIGNATURE_VERIFICATION
  ].freeze

  before_action :set_config
  before_action :allowed_configs
  def show
    # ref: https://github.com/rubocop/rubocop/issues/7767
    # rubocop:disable Style/HashTransformValues
    @app_config = InstallationConfig.where(name: @allowed_configs)
                                    .pluck(:name, :serialized_value)
                                    .map { |name, serialized_value| [name, serialized_value['value']] }
                                    .to_h
    # rubocop:enable Style/HashTransformValues
    @installation_configs = ConfigLoader.new.general_configs.each_with_object({}) do |config_hash, result|
      result[config_hash['name']] = config_hash.except('name')
    end
    load_openrouter_models if @config == 'captain' && Llm::Endpoint.openrouter?(@app_config['CAPTAIN_OPEN_AI_ENDPOINT'])
  end

  def create
    return unless valid_openrouter_models?

    errors = []
    params['app_config'].each do |key, value|
      next unless @allowed_configs.include?(key)

      i = InstallationConfig.where(name: key).first_or_create(value: value, locked: false)
      i.value = value
      errors.concat(i.errors.full_messages) unless i.save
    end

    if errors.any?
      redirect_to super_admin_app_config_path(config: @config), alert: errors.join(', ')
    else
      redirect_to super_admin_settings_path, flash: success_flash
    end
  end

  private

  def set_config
    @config = params[:config] || 'general'
  end

  def allowed_configs
    mapping = {
      'facebook' => %w[FB_APP_ID FB_VERIFY_TOKEN FB_APP_SECRET IG_VERIFY_TOKEN FACEBOOK_API_VERSION ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT],
      'shopify' => %w[SHOPIFY_CLIENT_ID SHOPIFY_CLIENT_SECRET],
      'microsoft' => %w[AZURE_APP_ID AZURE_APP_SECRET],
      'email' => %w[MAILER_INBOUND_EMAIL_DOMAIN ACCOUNT_EMAILS_LIMIT ACCOUNT_EMAILS_PLAN_LIMITS],
      'linear' => %w[LINEAR_CLIENT_ID LINEAR_CLIENT_SECRET],
      'slack' => %w[SLACK_CLIENT_ID SLACK_CLIENT_SECRET],
      'instagram' => INSTAGRAM_CONFIGS,
      'tiktok' => %w[TIKTOK_APP_ID TIKTOK_APP_SECRET TIKTOK_API_VERSION],
      'whatsapp_embedded' => %w[WHATSAPP_APP_ID WHATSAPP_APP_SECRET WHATSAPP_CONFIGURATION_ID WHATSAPP_API_VERSION],
      'notion' => %w[NOTION_CLIENT_ID NOTION_CLIENT_SECRET],
      'google' => GOOGLE_CONFIGS,
      'unoapi' => %w[UNOAPI_API_URL UNOAPI_AUTH_TOKEN],
      'captain' => %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_OPEN_AI_MODEL CAPTAIN_OPEN_AI_ENDPOINT CAPTAIN_AUDIO_TRANSCRIPTION_MODEL]
    }

    @allowed_configs = mapping.fetch(
      @config,
      %w[ENABLE_ACCOUNT_SIGNUP FIREBASE_PROJECT_ID FIREBASE_CREDENTIALS WEBHOOK_TIMEOUT MAXIMUM_FILE_UPLOAD_SIZE WIDGET_TOKEN_EXPIRY]
    )
  end

  def success_notice
    message = I18n.t('super_admin.config_saved')
    return message unless restart_required_config_saved?

    "#{message} #{I18n.t('super_admin.config_restart')}"
  end

  def load_openrouter_models
    catalog = Llm::OpenRouterCatalog.new
    @openrouter_models = {
      'CAPTAIN_OPEN_AI_MODEL' => catalog.models(feature: 'assistant'),
      'CAPTAIN_AUDIO_TRANSCRIPTION_MODEL' => catalog.models(feature: 'audio_transcription')
    }
  rescue Llm::OpenRouterCatalog::Unavailable
    flash.now[:alert] = I18n.t('super_admin.openrouter.catalog_unavailable')
    @openrouter_models = { 'CAPTAIN_OPEN_AI_MODEL' => [], 'CAPTAIN_AUDIO_TRANSCRIPTION_MODEL' => [] }
  end

  def valid_openrouter_models?
    return true unless @config == 'captain'

    values = params.fetch('app_config', {})
    endpoint = values['CAPTAIN_OPEN_AI_ENDPOINT'] || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    return true unless Llm::Endpoint.openrouter?(endpoint)

    return true unless invalid_openrouter_model?(values)

    redirect_to super_admin_app_config_path(config: @config), alert: I18n.t('super_admin.openrouter.invalid_model')
    false
  rescue Llm::OpenRouterCatalog::Unavailable
    redirect_to super_admin_app_config_path(config: @config), alert: I18n.t('super_admin.openrouter.catalog_unavailable')
    false
  end

  def invalid_openrouter_model?(values)
    catalog = Llm::OpenRouterCatalog.new
    OPENROUTER_MODEL_FEATURES.any? do |key, feature|
      value = values[key]
      next false if value.blank? || value == InstallationConfig.find_by(name: key)&.value

      !catalog.valid?(feature: feature, model: value)
    end
  end

  def success_flash
    restart_required_config_saved? ? { success: success_notice } : { notice: success_notice }
  end

  def restart_required_config_saved?
    params.fetch('app_config', {}).keys.intersect?(InstallationConfig::RESTART_REQUIRED_CONFIG_KEYS)
  end
end

SuperAdmin::AppConfigsController.prepend_mod_with('SuperAdmin::AppConfigsController')
