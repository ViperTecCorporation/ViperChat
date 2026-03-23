class FixUnoDefaultFeaturesAgain < ActiveRecord::Migration[7.0]
  FEATURES_TO_ENABLE = %w[
    agent_conversation_viewed
    agent_management
    automations
    crm
    crm_integration
    campaigns
    canned_responses
    channel_api
    channel_notifica_me
    channel_whatsapp
    chatwoot_v4
    custom_attributes
    custom_reply_domain
    custom_reply_email
    disable_branding
    disable_whatsapp_messaging_window
    channel_email
    email_continuity_on_api_channel
    channel_facebook
    help_center
    ip_lookup
    inbound_emails
    inbox_management
    channel_instagram
    integrations
    labels
    macros
    reports
    team_management
    voice_recorder
    channel_website
    whatsapp_campaign
    send_agent_name_in_whatsapp_message
    captain_integration
    captain_integration_v2
    custom_roles
    audit_logs
    sla
  ].freeze

  FEATURES_TO_DISABLE = %w[
    read_message
    saml
    linear_integration
    hide_all_chats_for_agent
    hide_filters_for_agent
    hide_contacts_for_agent
    hide_unassigned_for_agent
    agent_bots
    auto_resolve_conversations
  ].freeze

  def up
    enable_defaults_in_installation_config
    enable_features_on_existing_accounts
    update_pricing_plan_configs
    GlobalConfig.clear_cache
  end

  def down
    # no-op
  end

  private

  def enable_defaults_in_installation_config
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.blank? || config.value.blank?

    features = config.value.map do |feature|
      if FEATURES_TO_ENABLE.include?(feature['name'])
        feature.merge('enabled' => true)
      elsif FEATURES_TO_DISABLE.include?(feature['name'])
        feature.merge('enabled' => false)
      else
        feature
      end
    end

    config.value = features
    config.save!
  end

  def enable_features_on_existing_accounts
    features_to_enable = available_features(FEATURES_TO_ENABLE)
    features_to_disable = available_features(FEATURES_TO_DISABLE)

    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each do |account|
        account.enable_features!(*features_to_enable)
        account.disable_features!(*features_to_disable)
      end
    end
  end

  def available_features(feature_names)
    return feature_names if column_exists?(:accounts, :feature_flags_2)

    unavailable_feature_names = Featurable::SECONDARY_FEATURES.map { |feature| feature.to_s.delete_prefix('feature_') }
    feature_names - unavailable_feature_names
  end

  def update_pricing_plan_configs
    captain_limits_config =
      InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_CLOUD_PLAN_LIMITS')
    captain_limits_config.value = ''
    captain_limits_config.save!

    plan_config =
      InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
    plan_config.value = 'premium'
    plan_config.save!

    quantity_config =
      InstallationConfig.find_or_initialize_by(
        name: 'INSTALLATION_PRICING_PLAN_QUANTITY'
      )
    quantity_config.value = 1_000_000
    quantity_config.save!
  end
end
