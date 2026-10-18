require 'rails_helper'

RSpec.describe 'ViperERP contact replication', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/vipererp_contacts" }
  let(:cutoff) { (Time.current.to_i - 10) * 1_000_000 }

  it 'requires authentication' do
    get "#{path}/changes"
    expect(response).to have_http_status(:unauthorized)
  end

  it 'accepts the backend user API token with account membership' do
    token = admin.access_token || admin.create_access_token!
    get "#{path}/changes", headers: { api_access_token: token.token }
    expect(response).to have_http_status(:ok)
  end

  it 'denies non administrators' do
    agent = create(:user, account: account, role: :agent)
    get "#{path}/changes", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not expose another account' do
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/vipererp_contacts/changes", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'paginates with a stable tuple and a frozen upper bound, without total counts' do
    stamp = Time.at((cutoff / 1_000_000) - 60).utc
    contacts = create_list(:contact, 3, account: account)
    contacts.each { |contact| contact.update_columns(updated_at: stamp) } # rubocop:disable Rails/SkipsModelValidations
    create(:contact, account: create(:account)).update_columns(updated_at: stamp) # rubocop:disable Rails/SkipsModelValidations
    get "#{path}/changes", headers: headers, params: { since: 0, until: cutoff, limit: 2 }
    expect(response).to have_http_status(:ok)
    first = response.parsed_body
    expect(first['payload'].pluck('id')).to eq(contacts.first(2).map(&:id))
    expect(first['meta']['has_more']).to be(true)
    expect(first['meta']).not_to have_key('count')
    get "#{path}/changes", headers: headers,
                           params: { since: first['meta']['cursor_time'], after_id: first['meta']['cursor_id'], until: cutoff, limit: 2 }
    expect(response.parsed_body['payload'].pluck('id')).to eq([contacts.last.id])
    expect(response.parsed_body['meta']['has_more']).to be(false)
  end

  it 'rejects invalid or unbounded cursors' do
    [{ since: -1 }, { after_id: -1 }, { limit: 101 }, { since: 'bad' }, { until: cutoff + 3_600_000_000 }].each do |params|
      get "#{path}/changes", headers: headers, params: params
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'returns a compact versioned record without inboxes, private attributes or credentials' do
    contact = create(:contact, account: account, name: 'Original', phone_number: '+5566996222471')
    get "#{path}/#{contact.id}", headers: headers
    payload = response.parsed_body['payload']
    expect(payload.keys.sort).to eq(%w[id modified name phone_number version])
    expect(payload['version']).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'conditionally updates only shared fields and rejects a stale retry' do
    contact = create(:contact, account: account, name: 'Original', phone_number: '+5566996222471', identifier: 'keep', blocked: true,
                               custom_attributes: { private_field: 'keep' })
    get "#{path}/#{contact.id}", headers: headers
    version = response.parsed_body['payload']['version']
    fields = { expected_version: version, name: 'Atualizado', phone_number: '+5566996222471', blocked: false }
    patch "#{path}/#{contact.id}", headers: headers,
                                   params: fields, as: :json
    expect(response).to have_http_status(:ok)
    expect(contact.reload.name).to eq('Atualizado')
    expect(contact.blocked).to be(true)
    expect(contact.identifier).to eq('keep')
    expect(contact.custom_attributes).to eq('private_field' => 'keep')
    patch "#{path}/#{contact.id}", headers: headers,
                                   params: { expected_version: version, name: 'Sobrescrever', phone_number: '+5566996222471' }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(contact.reload.name).to eq('Atualizado')
  end

  it 'rejects invalid phone numbers without changing the record' do
    contact = create(:contact, account: account, name: 'Original', phone_number: '+5566996222471')
    get "#{path}/#{contact.id}", headers: headers
    fields = { expected_version: response.parsed_body['payload']['version'], name: 'Alterado', phone_number: '+999123456789' }
    patch "#{path}/#{contact.id}", headers: headers,
                                   params: fields, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contact.reload.name).to eq('Original')
  end
end
