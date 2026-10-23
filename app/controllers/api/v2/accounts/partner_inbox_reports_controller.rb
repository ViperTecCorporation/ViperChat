class Api::V2::Accounts::PartnerInboxReportsController < Api::V1::Accounts::BaseController
  SETTINGS_KEY = 'partner_inbox_report'.freeze
  SETTINGS_FIELDS = %i[timezone currency ad_window_days service_rate utility_rate marketing_rate authentication_rate].freeze

  before_action -> { authorize :report, :view? }
  rescue_from Whatsapp::PartnerInboxReportService::InvalidParameters do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def show
    permitted = params.permit(:from, :to, :link_id, :timezone, :ad_window_days,
                              :service_rate, :utility_rate, :marketing_rate, :authentication_rate)
    render json: Whatsapp::PartnerInboxReportService.new(account: Current.account, params: permitted).perform
  end

  def settings
    zone = Current.account.reporting_timezone.presence || Time.zone.tzinfo.name
    values = Current.account.settings.fetch(SETTINGS_KEY, {})
    defaults = values.fetch('currency', 'BRL') == 'BRL' ? Whatsapp::PartnerCostSimulationService::BRL_DEFAULT_RATES : {}
    render json: defaults.merge(values).merge('account_timezone' => ActiveSupport::TimeZone[zone].tzinfo.name)
  end

  def ad_leads
    permitted = params.permit(:from, :to, :timezone, :ad_window_days,
                              :service_rate, :utility_rate, :marketing_rate, :authentication_rate)
    render json: Whatsapp::AdLeadsReportService.new(account: Current.account, params: permitted).perform
  end

  def update_settings
    Current.account.with_lock do
      values = Current.account.settings.fetch(SETTINGS_KEY, {}).merge(params.permit(*SETTINGS_FIELDS).to_h)
      raise Whatsapp::PartnerInboxReportService::InvalidParameters, 'invalid_currency' unless %w[BRL USD].include?(values.fetch('currency', 'BRL'))

      # Reuse the simulator's input validation without reading message history.
      Whatsapp::PartnerInboxReportService.new(account: Current.account, params: values.merge(from: Date.current.iso8601, to: Date.current.iso8601))
      Current.account.update!(settings: Current.account.settings.merge(SETTINGS_KEY => values))
    end
    settings
  end
end
