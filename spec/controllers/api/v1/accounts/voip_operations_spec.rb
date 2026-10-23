require 'rails_helper'

RSpec.describe 'VoIP processing operations', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:service) do
    VoipService.create!(account: account, name: 'Central', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test',
                        credentials: { integration_provider: 'webhook', webhook_source_instance_id: 'pbx-1' })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/voip/services/#{service.id}" }
  let(:headers) { { 'api_access_token' => admin.access_token.token } }
  let!(:event) do
    VoipProviderEvent.create!(voip_service: service, source_instance_id: 'pbx-1', event_id: 'technical-event', provider_call_id: 'private-call-id',
                              revision: 1, content_digest: 'digest', payload: { 'private' => 'sensitive-payload' }, attempts: 8,
                              last_error_code: 'processing_failed')
  end
  let!(:external) { VoipExternalCall.create!(voip_service: service, source_instance_id: 'pbx-1', provider_call_id: 'private-external-id') }
  let!(:artifact) { external.create_voip_call_artifact!(state: 'failed', attempts: 8, snapshot: { 'secret' => 'sensitive-artifact' }) }

  it 'returns only sanitized administrator diagnostics within the current service and account' do
    get "#{url}/diagnostics", headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['counts']).to include('failed_events' => 1, 'failed_artifacts' => 1)
    expect(body['records'].map { |row| row.slice('kind', 'id', 'reprocessable') }).to contain_exactly(
      { 'kind' => 'event', 'id' => event.id, 'reprocessable' => true },
      { 'kind' => 'artifact', 'id' => artifact.id, 'reprocessable' => true }
    )
    expect(response.body).not_to match(/sensitive|private-call|private-external|payload|api_access_token/)
    get "#{url}/diagnostics", headers: { 'api_access_token' => agent.access_token.token }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'requeues without modifying event identity, payload, artifact target or stored history and audits the operator' do
    expect do
      post "#{url}/reprocess", params: { kind: 'event', record_id: event.id }, headers: headers, as: :json
    end.to have_enqueued_job(Voip::ProcessProviderEventJob).with(event.id)
    expect(response).to have_http_status(:accepted)
    expect(event.reload).to have_attributes(attempts: 0, last_error_code: nil, last_reprocessed_by_id: admin.id,
                                            event_id: 'technical-event', payload: { 'private' => 'sensitive-payload' })
    expect do
      post "#{url}/reprocess", params: { kind: 'artifact', record_id: artifact.id }, headers: headers, as: :json
    end.to have_enqueued_job(Voip::PublishCallArtifactJob).with(artifact.id)
    expect(artifact.reload).to have_attributes(state: 'pending', attempts: 0, snapshot: { 'secret' => 'sensitive-artifact' })
    post "#{url}/reprocess", params: { kind: 'event', record_id: event.id }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'rejects completed records, changed source, disabled service, invalid kind and foreign records' do
    event.update!(processed_at: Time.current)
    post "#{url}/reprocess", params: { kind: 'event', record_id: event.id }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    external.update!(source_instance_id: 'old-source')
    post "#{url}/reprocess", params: { kind: 'artifact', record_id: artifact.id }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    post "#{url}/reprocess", params: { kind: 'other', record_id: event.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{url}/reprocess", params: { kind: 'event', record_id: event.id + 999 }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    service.update!(enabled: false)
    post "#{url}/reprocess", params: { kind: 'event', record_id: event.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not expose another account service or accept an agent replay' do
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/voip/services/#{service.id}/diagnostics", headers: headers
    expect(response).not_to have_http_status(:ok)
    post "#{url}/reprocess", params: { kind: 'event', record_id: event.id },
                             headers: { 'api_access_token' => agent.access_token.token }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(event.reload.attempts).to eq(8)
  end

  it 'retains a durable replay request when job enqueue is unavailable' do
    allow(Voip::ProcessProviderEventJob).to receive(:perform_later).and_raise(StandardError, 'secret transport details')
    post "#{url}/reprocess", params: { kind: 'event', record_id: event.id }, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    expect(event.reload.attempts).to eq(0)
    expect(VoipProviderEvent.due).to include(event)
    expect(response.body).not_to include('secret transport')
  end

  it 'schedules scoped history recovery only for an administrator of a configured own-service integration' do
    service.credentials = service.credentials.merge('integration_provider' => 'viperconnect', 'history_api_url' => 'https://pbx.example.test',
                                                    'history_api_token' => 'synthetic-private-token', 'history_company_id' => 'synthetic-company')
    service.save!
    expect do
      post "#{url}/recover_history", params: { reset_cursor: true }, headers: headers, as: :json
    end.to have_enqueued_job(Voip::SyncHistoryJob).with(service.id)
    expect(response).to have_http_status(:accepted)
    expect(service.reload.history_sync_state.reset_requested).to be(true)
    expect(response.body).not_to include('token', 'cursor')
    post "#{url}/recover_history", params: { reset_cursor: 'true' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{url}/recover_history", params: {}, headers: { 'api_access_token' => agent.access_token.token }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
