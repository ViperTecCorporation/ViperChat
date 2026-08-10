class NativeAppController < ApplicationController
  NATIVE_API_VERSION = 1
  MAX_SHARE_FILES = 10

  def discovery
    render json: {
      schema: 1,
      product: 'viper-chat',
      installationId: ChatwootHub.installation_identifier,
      instanceName: GlobalConfigService.load('INSTALLATION_NAME', 'ViperChat'),
      version: Chatwoot.config[:version],
      apiVersion: NATIVE_API_VERSION,
      features: features,
      limits: limits,
      config: public_config
    }
  end

  private

  def features
    {
      nativeApp: true,
      nativePush: native_push_enabled?,
      nativeShare: true,
      webPush: VapidService.public_key.present?,
      voiceNotes: true,
      nativeVoiceCalls: false,
      nativeVideoCalls: false,
      locationSharing: false
    }
  end

  def limits
    max_attachment_size = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', '150').to_i.megabytes

    {
      maxAttachmentBytes: max_attachment_size,
      maxShareFiles: MAX_SHARE_FILES
    }
  end

  def public_config
    {
      directUploadsEnabled: ActiveModel::Type::Boolean.new.cast(
        GlobalConfigService.load('DIRECT_UPLOADS_ENABLED', 'false')
      ),
      mfaEnabled: Chatwoot.mfa_enabled?,
      allowedLoginMethods: ['email'],
      selectedLocale: I18n.default_locale.to_s
    }
  end

  def native_push_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('VIPER_NATIVE_PUSH_ENABLED', false)) &&
      ENV['VIPER_PUSH_RELAY_URL'].present? &&
      ENV['VIPER_PUSH_RELAY_TOKEN'].present?
  end
end
