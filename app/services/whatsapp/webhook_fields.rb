module Whatsapp::WebhookFields
  MESSAGING = %w[messages smb_message_echoes message_echoes].freeze
  GROUP = %w[group_lifecycle_update group_participants_update group_settings_update group_status_update].freeze
  ADMIN = %w[
    account_alerts account_review_update account_settings_update account_update automatic_events
    business_capability_update business_status_update business_username_updates flows history
    message_template_components_update message_template_quality_update message_template_status_update
    messaging_handovers partner_solutions payment_configuration_update phone_number_name_update
    phone_number_quality_update security smb_app_state_sync standby template_correct_category_detection
    tracking_events user_preferences
  ].freeze
  ALL = (MESSAGING + GROUP + ADMIN + %w[calls]).freeze
  # Optional fields may require additional permissions. Keep onboarding backwards compatible.
  DEFAULT = %w[messages smb_message_echoes].freeze
  TEMPLATE = %w[
    message_template_components_update message_template_quality_update message_template_status_update
    template_correct_category_detection
  ].freeze
  IMPORT = %w[history smb_app_state_sync].freeze
end
