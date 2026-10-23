require 'rails_helper'

RSpec.describe Api::V2::Accounts::PartnerInboxReportsController, type: :request do
  let(:account) { create(:account, settings: { 'unrelated' => 'preserved', 'reporting_timezone' => 'America/Cuiaba' }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v2/accounts/#{account.id}/reports/partner_inboxes/settings" }
  let(:values) do
    { 'timezone' => 'America/Cuiaba', 'currency' => 'BRL', 'ad_window_days' => '7',
      'service_rate' => '0.04', 'utility_rate' => 0, 'marketing_rate' => '', 'authentication_rate' => '' }
  end

  it 'returns the account timezone before the first save' do
    get path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(Whatsapp::PartnerCostSimulationService::BRL_DEFAULT_RATES.merge('account_timezone' => 'America/Cuiaba'))
    expect(account.reload.settings['partner_inbox_report']).to be_nil
  end

  it 'preserves saved blanks and does not apply BRL defaults to USD preferences' do
    headers = admin.create_new_auth_token
    account.update!(settings: account.settings.merge('partner_inbox_report' => { 'service_rate' => '', 'marketing_rate' => 0 }))
    get path, headers: headers
    expect(response.parsed_body).to include('service_rate' => '', 'marketing_rate' => 0, 'utility_rate' => '0.035')
    account.update!(settings: account.settings.merge('partner_inbox_report' => { 'currency' => 'USD' }))
    get path, headers: headers
    expect(response.parsed_body).not_to have_key('service_rate')
  end

  it 'saves per account, reloads, edits and clears rates without changing unrelated settings' do
    headers = admin.create_new_auth_token
    patch path, headers: headers, params: values.merge('from' => '2026-01-01', 'other' => 'ignored'), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(values.merge('account_timezone' => 'America/Cuiaba'))
    get path, headers: headers
    expect(response.parsed_body).to eq(values.merge('account_timezone' => 'America/Cuiaba'))
    patch path, headers: headers, params: { service_rate: '', currency: 'USD' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(values.merge('service_rate' => '', 'currency' => 'USD', 'account_timezone' => 'America/Cuiaba'))
    expect(account.reload.settings['unrelated']).to eq('preserved')
    expect(create(:account).settings['partner_inbox_report']).to be_nil
  end

  it 'uses account timezone for the report unless explicitly overridden' do
    headers = admin.create_new_auth_token
    report_path = "/api/v2/accounts/#{account.id}/reports/partner_inboxes"
    get report_path, headers: headers, params: { from: '2026-10-01', to: '2026-10-23' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('timezone' => 'America/Cuiaba', 'timezone_confirmed' => true, 'from' => '2026-10-01T00:00:00-04:00')
    get report_path, headers: headers, params: { from: '2026-10-01', to: '2026-10-23', timezone: 'UTC' }
    expect(response.parsed_body['timezone']).to eq('Etc/UTC')
    expect(account.reload.reporting_timezone).to eq('America/Cuiaba')
  end

  it 'uses the system timezone when the account has none' do
    account.update!(reporting_timezone: nil)
    get path, headers: admin.create_new_auth_token
    expect(response.parsed_body['account_timezone']).to eq(Time.zone.tzinfo.name)
  end

  [{ service_rate: '-1' }, { service_rate: '1000001' }, { utility_rate: 'NaN' },
   { timezone: 'not/a-zone' }, { ad_window_days: '9' }, { currency: 'invalid' }].each do |invalid|
    it "rejects invalid settings #{invalid.keys.first} without overwriting the previous values" do
      account.update!(settings: account.settings.merge('partner_inbox_report' => values))
      patch path, headers: admin.create_new_auth_token, params: invalid, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.settings['partner_inbox_report']).to eq(values)
    end
  end

  it 'denies reading and writing without report permission' do
    headers = agent.create_new_auth_token
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    patch path, headers: headers, params: values, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.reload.settings['partner_inbox_report']).to be_nil
  end

  it 'does not expose or change another account settings' do
    other = create(:account, settings: { 'partner_inbox_report' => values })
    other_path = "/api/v2/accounts/#{other.id}/reports/partner_inboxes/settings"
    headers = admin.create_new_auth_token
    get other_path, headers: headers
    expect(response).not_to have_http_status(:ok)
    patch other_path, headers: headers, params: { service_rate: '999' }, as: :json
    expect(response).not_to have_http_status(:ok)
    expect(other.reload.settings['partner_inbox_report']).to eq(values)
  end
end
