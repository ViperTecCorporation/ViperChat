require 'rails_helper'

RSpec.describe 'VoIP contact and extension directory', type: :request do
  let(:account) do
    create(:account).tap { |row| row.disable_features!('hide_contacts_for_agent') }
  end
  let(:agent) { create(:user, account: account, name: 'José Ramal') }
  let(:member) { agent.account_users.find_by!(account: account) }
  let(:headers) { agent.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/voip" }
  let!(:service) do
    VoipService.create!(account: account, name: 'Directory', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test')
  end
  let!(:binding) do
    VoipAgentExtension.create!(account_user: member, voip_service: service, extension: '1001', auth_username: 'private-auth-name',
                               credentials: { password: 'synthetic-secret' }, active: true)
  end
  let!(:contact) { create(:contact, account: account, name: 'Márcia Cliente', phone_number: '+5566991234567') }

  it 'searches contact accents and formatted phone digits without mutating identities' do
    before = contact.reload.attributes
    ['marcia', '+55 (66) 99123-4567'].each do |query|
      get "#{base}/directory", params: { service_id: service.id, kind: 'contacts', search: query }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['items'].sole).to include('kind' => 'contact', 'contact_id' => contact.id, 'address' => contact.phone_number)
    end
    expect(contact.reload.attributes).to eq(before)
  end

  it 'identifies exact normalized telephone only, never a LID, suffix, or name' do
    ['5566991234567', '+55 (66) 99123-4567'].each do |address|
      get "#{base}/identity", params: { service_id: service.id, address: address }, headers: headers
      expect(response.parsed_body['identity']).to include('contact_id' => contact.id)
    end
    ['991234567', '5566991234567@lid', 'Márcia Cliente'].each do |address|
      get "#{base}/identity", params: { service_id: service.id, address: address }, headers: headers
      expect(response.parsed_body['identity']).to be_nil
    end
  end

  it 'returns only same-service agents and no authentication fields or secrets' do
    second = VoipService.create!(account: account, name: 'Other', wss_url: 'wss://other.example.test/ws', sip_domain: 'other.example.test')
    other = create(:user, account: account)
    VoipAgentExtension.create!(account_user: other.account_users.find_by!(account: account), voip_service: second,
                               extension: '2002', auth_username: 'other-auth')
    VoipAgentExtension.create!(voip_service: service, extension: 'orphan', auth_username: 'orphan-auth')
    get "#{base}/directory", params: { service_id: service.id, kind: 'extensions', search: 'jose' }, headers: headers
    expect(response.parsed_body['items'].sole).to include('kind' => 'agent', 'user_id' => agent.id, 'address' => '1001')
    expect(response.body).not_to include('private-auth-name', 'other-auth', 'password', 'synthetic-secret', 'orphan')
    get "#{base}/identity", params: { service_id: service.id, address: '2002' }, headers: headers
    expect(response.parsed_body['identity']).to be_nil
  end

  it 'does not identify foreign contacts and forbids foreign or restricted services' do
    foreign_contact = create(:contact, phone_number: '+5511987654321')
    get "#{base}/identity", params: { service_id: service.id, address: foreign_contact.phone_number }, headers: headers
    expect(response.parsed_body['identity']).to be_nil
    foreign = VoipService.create!(account: create(:account), name: 'Foreign', wss_url: 'wss://foreign.example.test/ws', sip_domain: 'foreign.test')
    get "#{base}/directory", params: { service_id: foreign.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    service.update!(allowed_user_ids: [create(:user, account: account).id])
    get "#{base}/directory", params: { service_id: service.id }, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'honors the existing hidden contact policy for directory and identity' do
    account.enable_features!('hide_contacts_for_agent')
    get "#{base}/directory", params: { service_id: service.id }, headers: headers
    expect(response.parsed_body['items']).to be_empty
    get "#{base}/identity", params: { service_id: service.id, address: contact.phone_number }, headers: headers
    expect(response.parsed_body['identity']).to be_nil
    get "#{base}/identity", params: { service_id: service.id, address: '1001' }, headers: headers
    expect(response.parsed_body['identity']).to include('user_id' => agent.id)
  end

  it 'does not select among ambiguous normalized phone matches' do
    duplicate = create(:contact, account: account, phone_number: '+5511987654321')
    # Simulate a legacy imported formatted value that the normal contact writer would normalize.
    duplicate.update_columns(phone_number: '+55 (66) 99123-4567') # rubocop:disable Rails/SkipsModelValidations
    get "#{base}/identity", params: { service_id: service.id, address: contact.phone_number }, headers: headers
    expect(response.parsed_body['identity']).to be_nil
  end

  it 'excludes groups and contacts with no dialable telephone' do
    contact.update!(email: '12345@g.us')
    create(:contact, account: account, phone_number: nil)
    get "#{base}/directory", params: { service_id: service.id }, headers: headers
    expect(response.parsed_body['items']).to be_empty
  end

  it 'returns existing avatar URLs without storing a second avatar or changing call snapshots' do
    contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
    call = binding.voip_calls.create!(account: account, client_call_id: 'directory-call', direction: 'outgoing',
                                      remote_address: contact.phone_number, remote_name: 'Original snapshot',
                                      started_at: Time.current, last_observed_at: Time.current)
    original = call.attributes
    get "#{base}/calls/#{call.id}", headers: headers
    expect(response.parsed_body['remote_identity']).to include('name' => contact.name, 'avatar_url' => contact.avatar_url)
    expect(response.parsed_body['remote_identity']['avatar_url']).to be_present
    expect(call.reload.attributes).to eq(original)
    post "#{base}/favorites", params: { service_id: service.id, favorite: { name: 'Saved label', address: contact.phone_number } },
                              headers: headers, as: :json
    expect(response.parsed_body['remote_identity']).to include('contact_id' => contact.id)
    get "#{base}/favorites", headers: headers
    expect(response.parsed_body.sole['remote_identity']).to include('contact_id' => contact.id)
  end

  it 'paginates directory results by fifteen' do
    16.times do |index|
      create(:contact, account: account, name: "Directory #{index}", phone_number: "+551198765#{format('%04d', index)}")
    end
    get "#{base}/directory", params: { service_id: service.id, page: 1 }, headers: headers
    expect(response.parsed_body).to include('total' => 17, 'page' => 1)
    expect(response.parsed_body['items'].size).to eq(15)
    get "#{base}/directory", params: { service_id: service.id, page: 2 }, headers: headers
    expect(response.parsed_body['items'].size).to eq(2)
  end

  it 'paginates recent calls by five' do
    16.times do |index|
      binding.voip_calls.create!(account: account, client_call_id: "paged-#{index}", direction: 'outgoing', remote_address: '1001',
                                 started_at: Time.current + index.seconds, last_observed_at: Time.current)
    end
    get "#{base}/calls", params: { page: 1 }, headers: headers
    first_ids = response.parsed_body['items'].pluck('id')
    expect(response.parsed_body).to include('total' => 16, 'page' => 1)
    expect(first_ids.size).to eq(5)
    expect(response.parsed_body['items'].first['remote_identity']).to include('user_id' => agent.id)
    get "#{base}/calls", params: { page: 2 }, headers: headers
    expect(response.parsed_body['items'].size).to eq(5)
    expect(response.parsed_body['items'].pluck('id') & first_ids).to be_empty
  end

  it 'searches history by the current identified contact or agent name without rewriting snapshots' do
    call = binding.voip_calls.create!(account: account, client_call_id: 'identified-search', direction: 'incoming',
                                      remote_address: contact.phone_number, remote_name: 'Original',
                                      started_at: Time.current, last_observed_at: Time.current)
    get "#{base}/calls", params: { search: 'marcia' }, headers: headers
    expect(response.parsed_body['items'].pluck('id')).to eq([call.id])
    call.update!(remote_address: '1001')
    get "#{base}/calls", params: { search: 'jose' }, headers: headers
    expect(response.parsed_body['items'].pluck('id')).to eq([call.id])
    expect(call.reload.remote_name).to eq('Original')
  end
end
