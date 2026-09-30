require 'rails_helper'

RSpec.describe 'Super Admin Application Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/app_config' do
    it 'shows the compatibility default for Gmail API before the setting is saved' do
      InstallationConfig.where(name: 'GOOGLE_GMAIL_API_ENABLED').destroy_all
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/app_config?config=google'
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      selected = page.at_css('select[name="app_config[GOOGLE_GMAIL_API_ENABLED]"] option[selected]')
      expect(selected['value']).to eq('false')
    end

    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/app_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      let!(:config) do
        InstallationConfig.find_or_initialize_by(name: 'FB_APP_ID').tap { |setting| setting.update!(value: 'TESTVALUE') }
      end

      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=facebook'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(config.value)
      end
    end
  end

  describe 'POST /super_admin/app_config' do
    it 'saves Gmail API as the new connection default without requiring a restart' do
      sign_in(super_admin, scope: :super_admin)
      post '/super_admin/app_config?config=google', params: { app_config: { GOOGLE_GMAIL_API_ENABLED: 'true' } }
      expect(response).to redirect_to(super_admin_settings_path)
      expect(InstallationConfig.find_by!(name: 'GOOGLE_GMAIL_API_ENABLED').value).to eq('true')
      expect(flash[:notice]).to be_present
      expect(flash[:success]).to be_blank
    end

    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        post '/super_admin/app_config', params: { app_config: { TESTKEY: 'TESTVALUE' } }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an aunthenticated super admin' do
      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=facebook', params: { app_config: { FB_APP_ID: 'FB_APP_ID' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:notice]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:success]).to be_blank

        config = GlobalConfig.get('FB_APP_ID')
        expect(config['FB_APP_ID']).to eq('FB_APP_ID')
      end

      it 'asks admins to restart web and worker processes for runtime config changes' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain', params: { app_config: { CAPTAIN_OPEN_AI_ENDPOINT: 'https://api.openai.com' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:success]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:notice]).to be_blank
      end
    end
  end
end
