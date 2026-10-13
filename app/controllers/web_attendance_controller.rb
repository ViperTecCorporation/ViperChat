class WebAttendanceController < ApplicationController
  def show
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    render layout: false
  end
end
