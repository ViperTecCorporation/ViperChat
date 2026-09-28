require 'rails_helper'

describe 'Location map frame', type: :request do
  it 'renders an isolated static preview without caching the browser key' do
    allow(GlobalConfigService).to receive(:load).with('GOOGLE_MAPS_API_KEY', '').and_return('public-browser-key')
    allow_any_instance_of(ActionView::Base).to receive(:vite_javascript_tag).with('location_preview').and_return('')
    get '/location-map/preview', params: { lat: '-11.5', lng: '-54.8' }
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.headers['Content-Security-Policy']).to include("frame-ancestors 'self' capacitor://localhost")
    expect(response.body).to include('id="location-preview"')
  end
  it 'limits framing to this installation and native local origins and disables caching' do
    allow(GlobalConfigService).to receive(:load).with('GOOGLE_MAPS_API_KEY', '').and_return('public-browser-key')
    # Asset compilation is verified by the production build, independently of this request spec.
    allow_any_instance_of(ActionView::Base).to receive(:vite_javascript_tag).and_return('')
    get '/location-map'
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.headers['Content-Security-Policy']).to eq("frame-ancestors 'self' capacitor://localhost https://localhost http://localhost")
    expect(response.headers['X-Frame-Options']).to be_nil
    expect(response.body).to include('data-api-key="public-browser-key"')
  end
end
