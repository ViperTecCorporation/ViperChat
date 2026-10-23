class Api::V2::Accounts::PartnerInboxReportsController < Api::V1::Accounts::BaseController
  def show
    authorize :report, :view?
    permitted = params.permit(:from, :to, :link_id, :timezone, :ad_window_days,
                              :service_rate, :utility_rate, :marketing_rate, :authentication_rate)
    render json: Whatsapp::PartnerInboxReportService.new(account: Current.account, params: permitted).perform
  rescue Whatsapp::PartnerInboxReportService::InvalidParameters => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
