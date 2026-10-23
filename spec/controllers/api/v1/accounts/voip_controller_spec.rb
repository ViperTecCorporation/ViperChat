require 'rails_helper'

RSpec.describe 'Agent VoIP API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { agent.account_users.find_by!(account: account) }
  let(:headers) { agent.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/voip" }
  let!(:service) do
    VoipService.create!(account: account, name: 'Test central', wss_url: 'wss://sip.example.test/sip/ws', sip_domain: 'sip.example.test')
  end
  let!(:binding) do
    VoipAgentExtension.create!(account_user: member, voip_service: service, extension: '0010', auth_username: '0010',
                               credentials: { password: 'synthetic-sip-secret' }, active: true)
  end
  let(:call_attributes) { { client_call_id: 'client-call-1', sip_call_id: 'sip-call-1', direction: 'outgoing', remote_address: '0020' } }
  let!(:call) do
    binding.voip_calls.create!(account: account, **call_attributes, remote_name: 'José Teste', started_at: Time.current,
                               last_observed_at: Time.current)
  end

  it 'rejects unauthenticated access' do
    get "#{base}/profile"
    expect(response).to have_http_status(:unauthorized)
  end

  it 'authorizes recording downloads against the visible call, never a foreign account or another agent' do
    external = VoipExternalCall.create!(voip_service: service, source_instance_id: 'test', provider_call_id: 'call-1')
    call.update!(voip_external_call: external)
    artifact = external.create_voip_call_artifact!
    artifact.recording.attach(io: StringIO.new('test-audio'), filename: 'call.wav', content_type: 'audio/wav')
    get "#{base}/calls/#{call.id}/recording", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('test-audio')
    expect(response.headers).to include('Content-Type' => 'audio/wav', 'Cache-Control' => 'private, no-store')
    expect(response.headers['Location']).to be_nil
    stranger = create(:user, account: account, role: :agent)
    get "#{base}/calls/#{call.id}/recording", headers: stranger.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    foreign = create(:user)
    get "#{base}/calls/#{call.id}/recording", headers: foreign.create_new_auth_token
    expect(response).not_to have_http_status(:ok)
  end

  it 'lists configured extensions for administrators without exposing credentials or foreign bindings' do
    get "#{base}/services", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.sole['bindings'].sole).to include('id' => binding.id, 'agent_name' => agent.name, 'extension' => '0010')
    expect(response.body).not_to include('synthetic-sip-secret', 'encrypted_credentials', 'auth_username')
    get "#{base}/services", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows an administrator to edit WSS while rejecting insecure LAN WS without changing credentials' do
    secret = binding.encrypted_credentials
    patch "#{base}/services/#{service.id}", params: { service: { wss_url: 'ws://192.168.0.143:3097/sip/ws' } },
                                            headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['attributes']).to include('wss_url')
    patch "#{base}/services/#{service.id}", params: { service: { name: 'Updated', wss_url: 'wss://sip.lan.test/sip/ws' } },
                                            headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(service.reload.name).to eq('Updated')
    expect(binding.reload.encrypted_credentials).to eq(secret)
  end

  it 'revokes removed agents without losing history or allowing bootstrap of their detached binding' do
    service.update!(allowed_user_ids: [agent.id])
    VoipFavorite.create!(account_user: member, voip_service: service, name: 'Test favorite', address: '0020')
    observation = call.voip_call_observations.create!(event_id: 'preserved-event', sequence: 1, state: 'ringing')
    original_call = call.attributes
    member.destroy!
    expect(binding.reload).to have_attributes(account_user_id: nil, active: false, encrypted_credentials: nil)
    expect(call.reload.attributes).to eq(original_call)
    expect(call.public_payload[:agent_id]).to eq(agent.id)
    expect(observation.reload.voip_call_id).to eq(call.id)
    expect(VoipFavorite.where(account_user_id: member.id)).to be_empty
    post "#{base}/registration", params: { binding_id: binding.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    get "#{base}/calls/#{call.id}", headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('id' => call.id, 'agent_id' => agent.id, 'extension' => '0010')
  end

  it 'allows safe extension reassignment without broadening a restricted service allowlist' do
    service.update!(allowed_user_ids: [agent.id])
    member.destroy!
    service.update!(name: 'Still restricted')
    expect(service.reload.allowed_user_ids).to eq([agent.id])
    expect(service.available_to?(admin.account_users.find_by!(account: account))).to be(true)
    replacement = create(:user, account: account)
    replacement_member = replacement.account_users.find_by!(account: account)
    expect(service.available_to?(replacement_member)).to be(false)
    replacement_binding = VoipAgentExtension.create!(account_user: replacement_member, voip_service: service,
                                                     extension: '0010', auth_username: '0010')
    expect(replacement_binding.credentials).to eq({})
  end

  it 'supports intentional account deletion without orphaning VoIP rows or blocking the existing deletion flow' do
    VoipFavorite.create!(account_user: member, voip_service: service, name: 'Test favorite', address: '0020')
    observation = call.voip_call_observations.create!(event_id: 'account-event', sequence: 1, state: 'ringing')
    account.destroy!
    expect(Account.exists?(account.id)).to be(false)
    expect(VoipCall.exists?(call.id)).to be(false)
    expect(VoipCallObservation.exists?(observation.id)).to be(false)
    expect(VoipAgentExtension.exists?(binding.id)).to be(false)
    expect(VoipService.exists?(service.id)).to be(false)
    expect(VoipFavorite.where(account_user_id: member.id)).to be_empty
  end

  it 'preserves both histories when different agents leave the same service consecutively' do
    other = create(:user, account: account)
    other_member = other.account_users.find_by!(account: account)
    other_binding = VoipAgentExtension.create!(account_user: other_member, voip_service: service, extension: '0011', auth_username: '0011',
                                               credentials: { password: 'second-synthetic-secret' }, active: true)
    other_call = other_binding.voip_calls.create!(account: account, **call_attributes, started_at: Time.current, last_observed_at: Time.current)
    member.destroy!
    other_member.destroy!
    expect([binding.reload, other_binding.reload]).to all(have_attributes(account_user_id: nil, active: false, encrypted_credentials: nil))
    expect(call.reload.public_payload).to include(agent_id: agent.id, extension: '0010')
    expect(other_call.reload.public_payload).to include(agent_id: other.id, extension: '0011')
    call.update!(end_reason: 'historical_audit')
    expect(call.reload.end_reason).to eq('historical_audit')
    expect(VoipCall.where(id: [call.id, other_call.id]).count).to eq(2)
  end

  it 'preserves the historical extension when the agent reconfigures their binding' do
    binding.update!(extension: '0011')
    expect(call.reload.public_payload[:extension]).to eq('0010')
  end

  it 'finds formatted phone numbers without changing contact or call identifiers' do
    call.update!(remote_address: '+5566991234567')
    get "#{base}/calls", params: { search: '+55 (66) 99123-4567' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['items'].map { |row| row['id'] }).to eq([call.id])
  end

  it 'rejects reuse of an event id with a conflicting state' do
    post "#{base}/calls/#{call.id}/observe", params: { observation: { event_id: 'same-event', sequence: 1, state: 'ringing' } },
                                             headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    post "#{base}/calls/#{call.id}/observe", params: { observation: { event_id: 'same-event', sequence: 1, state: 'ended' } },
                                             headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(call.reload.state).to eq('ringing')
    expect(call.voip_call_observations.count).to eq(1)
  end

  it 'encrypts extension and TURN credentials, never exposing them in list or profile JSON' do
    service.update!(credentials: { turn_url: 'turn:turn.example.test', turn_password: 'synthetic-turn-secret' })
    expect(binding.encrypted_credentials).not_to include('synthetic-sip-secret')
    expect(service.encrypted_credentials).not_to include('synthetic-turn-secret')
    get "#{base}/profile", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('synthetic-sip-secret', 'synthetic-turn-secret', 'encrypted_credentials')
    expect(response.parsed_body['bindings'].sole['extension']).to eq('0010')
  end

  it 'returns only the own bootstrap with no-store headers' do
    post "#{base}/registration", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body).to include('password' => 'synthetic-sip-secret', 'extension' => '0010')
  end

  it 'does not allow another agent or account to bootstrap a binding' do
    other = create(:user, account: account)
    post "#{base}/registration", params: { binding_id: binding.id }, headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    foreign = create(:user)
    post "#{base}/registration", headers: foreign.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'requires administrator privileges for shared service mutations' do
    patch "#{base}/services/#{service.id}", params: { service: { name: 'Unauthorized' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(service.reload.name).to eq('Test central')
  end

  it 'allows administrator service creation but rejects cross-account allowlists' do
    payload = { name: 'Second service', wss_url: 'wss://second.example.test/ws', sip_domain: 'second.example.test', allowed_user_ids: [agent.id] }
    expect do
      post "#{base}/services", params: { service: payload }, headers: admin.create_new_auth_token, as: :json
    end.to change(VoipService, :count).by(1)
    expect(response).to have_http_status(:created)
    foreign = create(:user)
    post "#{base}/services", params: { service: payload.merge(allowed_user_ids: [foreign.id]) }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'preserves omitted credentials and clears only on explicit request' do
    call.update!(state: 'ended')
    patch "#{base}/profile", params: { service_id: service.id, binding: { extension: '0011', auth_username: 'auth11' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(binding.reload.credentials['password']).to eq('synthetic-sip-secret')
    patch "#{base}/profile", params: { service_id: service.id, binding: { clear_password: true } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(binding.reload.credentials['password']).to be_nil
  end

  it 'respects the administrator preference denying agent self-configuration' do
    service.update!(allow_self_configuration: false)
    patch "#{base}/profile", params: { service_id: service.id, binding: { extension: '0011' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(binding.reload.extension).to eq('0010')
  end

  it 'prevents switching or editing an extension during a live call' do
    post "#{base}/profile/activate", params: { binding_id: binding.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch "#{base}/profile", params: { service_id: service.id, binding: { extension: '0011' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(binding.reload.extension).to eq('0010')
  end

  it 'allows same extension at another service without copying the password' do
    call.update!(state: 'ended')
    second = VoipService.create!(account: account, name: 'Other', wss_url: 'wss://other.example.test/ws', sip_domain: 'other.example.test')
    patch "#{base}/profile", params: { service_id: second.id, binding: { extension: '0010', auth_username: '0010' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(VoipAgentExtension.find_by!(account_user: member, voip_service: second).credentials).to eq({})
    expect(binding.reload.credentials['password']).to eq('synthetic-sip-secret')
  end

  it 'rejects using a disabled or unauthorized service' do
    service.update!(enabled: false)
    post "#{base}/registration", headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    service.update!(enabled: true, allowed_user_ids: [admin.id])
    post "#{base}/registration", headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'archives services without deleting their bindings, calls or history' do
    before = [binding.attributes, call.attributes, VoipService.count]
    delete "#{base}/services/#{service.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:no_content)
    expect(service.reload.enabled).to be(false)
    expect([binding.reload.attributes, call.reload.attributes, VoipService.count]).to eq(before)
  end

  it 'deduplicates creation by client call ID without creating a contact or conversation' do
    before = [VoipCall.count, Contact.count, Conversation.count, Attachment.count]
    2.times { post "#{base}/calls", params: { binding_id: binding.id, call: call_attributes }, headers: headers, as: :json }
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['id']).to eq(call.id)
    expect([VoipCall.count, Contact.count, Conversation.count, Attachment.count]).to eq(before)
  end

  it 'rejects reusing a call ID for a different destination' do
    post "#{base}/calls", params: { binding_id: binding.id, call: call_attributes.merge(remote_address: '9999') }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(call.reload.remote_address).to eq('0020')
  end

  it 'persists idempotent observations and never reopens a terminal call' do
    [{ event_id: 'answered', sequence: 2, state: 'active' }, { event_id: 'old', sequence: 1, state: 'ringing' },
     { event_id: 'ended', sequence: 3, state: 'ended' }, { event_id: 'late', sequence: 4, state: 'active' }].each do |observation|
      2.times { post "#{base}/calls/#{call.id}/observe", params: { observation: observation }, headers: headers, as: :json }
      expect(response).to have_http_status(:ok)
    end
    expect(call.reload).to have_attributes(state: 'ended', last_sequence: 3)
    expect(call.answered_at).to be_present
    expect(call.ended_at).to be_present
    expect(call.voip_call_observations.count).to eq(4)
  end

  it 'does not let another agent fabricate observations or see private call history' do
    other = create(:user, account: account)
    post "#{base}/calls/#{call.id}/observe", params: { observation: { event_id: 'forged', sequence: 1, state: 'active' } },
                                             headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    get "#{base}/calls", headers: other.create_new_auth_token
    expect(response.parsed_body['items']).to be_empty
  end

  it 'retains an incoming microphone denial without fabricating an answer or changing call identity' do
    call.update!(direction: 'incoming', state: 'ringing')
    original_identity = call.attributes.slice('id', 'client_call_id', 'sip_call_id', 'remote_address', 'account_user_id', 'voip_service_id')
    observation = { event_id: 'microphone-denied', sequence: 2, state: 'failed', end_reason: 'microphone_denied' }
    2.times do
      post "#{base}/calls/#{call.id}/observe", params: { observation: observation }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(call.reload).to have_attributes(state: 'failed', end_reason: 'microphone_denied', answered_at: nil, last_sequence: 2)
    expect(call.ended_at).to be_present
    expect(call.attributes.slice(*original_identity.keys)).to eq(original_identity)
    expect(call.voip_call_observations.count).to eq(1)
    expect(call.voip_call_observations.sole.details).to include('end_reason' => 'microphone_denied')
    get "#{base}/calls/#{call.id}", headers: headers
    expect(response.parsed_body).to include('id' => call.id, 'state' => 'failed', 'end_reason' => 'microphone_denied', 'duration' => nil)
  end

  it 'marks expired observations as awaiting confirmation without fabricating a final result or duration' do
    call.update!(last_observed_at: 2.minutes.ago)
    get "#{base}/calls", params: { state: 'awaiting_confirmation' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['items'].sole).to include('state' => 'awaiting_confirmation', 'duration' => nil)
    expect(call.reload).to have_attributes(state: 'initiating', ended_at: nil)
  end

  it 'searches accent-free and by extension with backend pagination' do
    get "#{base}/calls", params: { search: 'jose' }, headers: headers
    expect(response.parsed_body['items'].pluck('id')).to eq([call.id])
    get "#{base}/calls", params: { search: '0010' }, headers: headers
    expect(response.parsed_body['items'].pluck('id')).to eq([call.id])
  end

  it 'keeps favorite ownership scoped to service and agent' do
    2.times do
      post "#{base}/favorites", params: { service_id: service.id, favorite: { name: 'Testing', address: '0020' } }, headers: headers, as: :json
    end
    expect(response).to have_http_status(:created)
    expect(VoipFavorite.where(account_user: member).count).to eq(1)
    other = create(:user, account: account)
    delete "#{base}/favorites/#{VoipFavorite.sole.id}", headers: other.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
