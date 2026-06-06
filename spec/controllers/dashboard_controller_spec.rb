require 'rails_helper'

describe '/app/login', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }

  before do
    allow_any_instance_of(ActionView::Base).to receive(:vite_client_tag).and_return('')
    allow_any_instance_of(ActionView::Base).to receive(:vite_javascript_tag).and_return('')
  end

  context 'without DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      get '/app/login'
      expect(response).to have_http_status(:success)
    end
  end

  context 'with DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      with_modified_env DEFAULT_LOCALE: 'pt_BR' do
        get '/app/login'
        expect(response).to have_http_status(:success)
        expect(response.body).to include "selectedLocale: 'pt_BR'"
      end
    end
  end

  context 'with non-HTML format' do
    it 'returns not acceptable for JSON with error message' do
      get '/app/login', headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:not_acceptable)
      expect(response.parsed_body).to eq({ 'error' => 'Please use API routes instead of dashboard routes for JSON requests' })
    end
  end

  # Routes are loaded once on app start
  # hence Rails.application.reload_routes! is used in this spec
  # ref : https://stackoverflow.com/a/63584877/939299
  context 'with CW_API_ONLY_SERVER true' do
    it 'returns 404' do
      with_modified_env CW_API_ONLY_SERVER: 'true' do
        Rails.application.reload_routes!
        get '/app/login'
        expect(response).to have_http_status(:not_found)
      end
      Rails.application.reload_routes!
    end
  end
end

RSpec.describe 'Dashboard', type: :request do
  before do
    allow_any_instance_of(ActionView::Base).to receive(:vite_client_tag).and_return('')
    allow_any_instance_of(ActionView::Base).to receive(:vite_javascript_tag).and_return('')
  end

  describe 'GET /' do
    context 'when installation has no accounts or super admins' do
      it 'redirects to installation onboarding' do
        expect(Account.count).to eq(0)
        expect(SuperAdmin.count).to eq(0)

        get '/'

        expect(response).to redirect_to('/installation/onboarding')
      end
    end

    context 'when installation is already configured' do
      let!(:super_admin) { create(:super_admin) }
      let!(:account) { create(:account) }

      it 'does not redirect to installation onboarding' do
        get '/'

        expect(response).not_to redirect_to('/installation/onboarding')
      end
    end
  end
end
