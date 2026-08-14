require 'rails_helper'

RSpec.describe 'Profile Super Admin Session API', type: :request do
  it 'returns a one-time native session URL for an authenticated Super Admin' do
    super_admin = create(:super_admin)
    auth_headers = super_admin.create_new_auth_token

    post '/api/v1/profile/super_admin_session', headers: auth_headers, as: :json

    expect(response).to have_http_status(:ok)
    uri = URI.parse(response.parsed_body['url'])
    query = Rack::Utils.parse_query(uri.query)
    expect(uri.path).to eq('/super_admin/native_session')
    expect(query['email']).to eq(super_admin.email)
    expect(super_admin.valid_sso_auth_token?(query['sso_auth_token'])).to be(true)
  end

  it 'rejects an authenticated regular user' do
    user = create(:user)

    post '/api/v1/profile/super_admin_session', headers: user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'requires authentication' do
    post '/api/v1/profile/super_admin_session', as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
