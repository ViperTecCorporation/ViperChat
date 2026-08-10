require 'rails_helper'

RSpec.describe 'Viper Chat native discovery', type: :request do
  describe 'GET /.well-known/viper-chat' do
    before do
      allow(ChatwootHub).to receive(:installation_identifier).and_return('inst-123')
      allow(Chatwoot).to receive(:config).and_return({ version: '4.16.11-viper' })
      allow(Chatwoot).to receive(:mfa_enabled?).and_return(true)
      allow(VapidService).to receive(:public_key).and_return('vapid-public-key')
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('INSTALLATION_NAME', 'ViperChat').and_return('Viper Tec')
      allow(GlobalConfigService).to receive(:load).with('MAXIMUM_FILE_UPLOAD_SIZE', '150').and_return('50')
      allow(GlobalConfigService).to receive(:load).with('DIRECT_UPLOADS_ENABLED', 'false').and_return('true')
    end

    it 'returns the versioned native capabilities without authentication' do
      get '/.well-known/viper-chat'

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'schema' => 1,
        'product' => 'viper-chat',
        'installationId' => 'inst-123',
        'instanceName' => 'Viper Tec',
        'version' => '4.16.11-viper',
        'apiVersion' => 1,
        'features' => include(
          'nativeApp' => true,
          'nativePush' => false,
          'nativeShare' => true,
          'webPush' => true,
          'voiceNotes' => true,
          'nativeVoiceCalls' => false,
          'locationSharing' => false
        ),
        'limits' => {
          'maxAttachmentBytes' => 50.megabytes,
          'maxShareFiles' => 10
        },
        'config' => {
          'directUploadsEnabled' => true,
          'mfaEnabled' => true,
          'allowedLoginMethods' => ['email'],
          'selectedLocale' => I18n.default_locale.to_s
        }
      )
    end

    it 'only advertises native push when the relay is fully configured' do
      with_modified_env(
        VIPER_NATIVE_PUSH_ENABLED: 'true',
        VIPER_PUSH_RELAY_URL: 'https://push.vipertec.net',
        VIPER_PUSH_RELAY_TOKEN: 'secret'
      ) do
        get '/.well-known/viper-chat'
      end

      expect(response.parsed_body.dig('features', 'nativePush')).to be(true)
    end
  end
end
