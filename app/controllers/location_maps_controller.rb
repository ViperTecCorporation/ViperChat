class LocationMapsController < ApplicationController
  before_action :configure_frame

  def show
    render layout: false
  end

  def preview
    render layout: false
  end

  private

  def configure_frame
    Rack::MiniProfiler.discard_results if defined?(Rack::MiniProfiler)
    response.headers.delete('X-Frame-Options')
    response.headers['Content-Security-Policy'] = "frame-ancestors 'self' capacitor://localhost https://localhost http://localhost"
    response.headers['Cache-Control'] = 'no-store'
    @maps_key = GlobalConfigService.load('GOOGLE_MAPS_API_KEY', '')
  end
end
