require 'rails_helper'

RSpec.describe 'VoIP integration configuration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/voip" }
  let!(:service) do
    VoipService.create!(account: account, name: 'Central', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test')
  end

  it 'returns the server-generated callback and accepts webhook without AMI or REST' do
    patch "#{base}/services/#{service.id}", params: { service: { integration_provider: 'webhook', webhook_source_instance_id: 'pbx-1' } },
                                            headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['webhook_url']).to end_with("#{base}/services/#{service.id}/events")
    expect(service.reload.integration_provider).to eq('webhook')
  end

  it 'preserves omitted credentials including obsolete AMI without exposing them' do
    service.update!(credentials: { 'ami_password' => 'old-secret', 'turn_password' => 'turn-secret', 'history_api_token' => 'history-secret' })
    patch "#{base}/services/#{service.id}", params: { service: { name: 'Updated', history_api_token: '' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('old-secret', 'turn-secret', 'history-secret', 'ami_password')
    expect(service.reload.credentials).to include('ami_password' => 'old-secret', 'history_api_token' => 'history-secret')
  end
end
