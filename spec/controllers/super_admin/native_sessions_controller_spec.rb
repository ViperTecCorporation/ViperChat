require 'rails_helper'

RSpec.describe SuperAdmin::NativeSessionsController, type: :request do
  it 'consumes the one-time token, signs in and redirects to the console' do
    super_admin = create(:super_admin)
    token = super_admin.generate_sso_auth_token

    get '/super_admin/native_session', params: { email: super_admin.email, sso_auth_token: token }

    expect(response).to redirect_to('/super_admin')
    expect(super_admin.valid_sso_auth_token?(token)).to be(false)
    expect(session['warden.user.super_admin.key'].first).to eq([super_admin.id])
  end

  it 'rejects an invalid or already consumed token' do
    super_admin = create(:super_admin)
    token = super_admin.generate_sso_auth_token

    get '/super_admin/native_session', params: { email: super_admin.email, sso_auth_token: token }
    expect(response).to redirect_to('/super_admin')

    get '/super_admin/native_session', params: { email: super_admin.email, sso_auth_token: token }
    expect(response).to have_http_status(:unauthorized)
  end
end
