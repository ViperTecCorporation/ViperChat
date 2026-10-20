require 'rails_helper'

RSpec.describe 'WhatsApp inbox links API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '5566996222471',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:path) { "/api/v1/accounts/#{account.id}/inboxes/#{uno.id}/whatsapp_link" }
  let(:headers) { admin.create_new_auth_token }
  let(:attributes) { { partner_inbox_id: meta.id, primary_inbox_id: uno.id, default_provider: 'whatsapp_cloud' } }

  before { account.enable_features!('inbox_management') }

  it 'requires authentication and administrator authorization even for preview and candidates' do
    get path
    expect(response).to have_http_status(:unauthorized)
    create(:inbox_member, user: agent, inbox: uno)
    create(:inbox_member, user: agent, inbox: meta)
    get path, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/preview", headers: agent.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    put path, headers: agent.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    delete path, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'requires the inbox management account feature' do
    uno
    meta
    account.disable_features!('inbox_management')
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'only returns matching same-account candidates and never credentials' do
    meta
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5566991111111',
                              sync_templates: false, validate_provider_config: false)
    create(:channel_whatsapp, provider: 'whatsapp_cloud', phone_number: '556696222471',
                              sync_templates: false, validate_provider_config: false)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['link']).to be_nil
    expect(response.parsed_body['candidates']).to eq([{ 'id' => meta.id, 'name' => meta.name, 'provider' => 'whatsapp_cloud' }])
    expect(response.body).not_to include('api_key', 'provider_config', 'test_key')
  end

  it 'creates a disabled draft and permits Meta as primary independently of the default transport' do
    put path, headers: headers, params: attributes.merge(primary_inbox_id: meta.id, default_provider: 'unoapi'), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['link']).to include('enabled' => false, 'activated_at' => nil,
                                                    'primary_inbox_id' => meta.id, 'secondary_inbox_id' => uno.id, 'default_provider' => 'unoapi')
  end

  it 'persists the optional initial Meta rule and preserves it when an older client omits the fields' do
    put path, headers: headers, params: attributes.merge(meta_initial_messages_enabled: true, meta_initial_messages_limit: 10), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['link']).to include('meta_initial_messages_enabled' => true, 'meta_initial_messages_limit' => 10)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['link']).to include('meta_initial_messages_enabled' => true, 'meta_initial_messages_limit' => 10)
    put path, headers: headers, params: attributes.merge(default_provider: 'unoapi'), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['link']).to include('meta_initial_messages_enabled' => true, 'meta_initial_messages_limit' => 10)
    expect(WhatsappMetaCycleSlot.count).to eq(0)
  end

  it 'updates policy on an active link despite historical conflicts and reads it back from either inbox' do
    put path, headers: headers, params: attributes.merge(enabled: true), as: :json
    expect(response).to have_http_status(:ok)
    link = WhatsappInboxLink.find(response.parsed_body.dig('link', 'id'))
    cutoff = link.activated_at
    contact = create(:contact, account: account)
    create(:conversation, account: account, inbox: uno, contact: contact, status: :open)
    create(:conversation, account: account, inbox: meta, contact: contact, status: :pending)

    put path, headers: headers,
              params: attributes.merge(enabled: true, meta_initial_messages_enabled: true, meta_initial_messages_limit: 5), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('preview', 'conflicts')).not_to be_empty
    expect(link.reload.activated_at).to eq(cutoff)
    expect(link).to have_attributes(primary_inbox_id: uno.id, secondary_inbox_id: meta.id)
    [uno, meta].each do |inbox|
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_link", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['link']).to include('id' => link.id, 'meta_initial_messages_enabled' => true,
                                                      'meta_initial_messages_limit' => 5)
    end
  end

  [-1, 1001, 1.5, 'invalid'].each do |limit|
    it "rejects an invalid initial Meta limit #{limit.inspect} without creating a link" do
      put path, headers: headers, params: attributes.merge(meta_initial_messages_enabled: true, meta_initial_messages_limit: limit), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(WhatsappInboxLink.count).to eq(0)
    end
  end

  it 'binds preview confirmation to the initial Meta settings as well as the inbox pair' do
    put path, headers: headers, params: attributes, as: :json
    link = WhatsappInboxLink.find(response.parsed_body.dig('link', 'id'))
    previous = Whatsapp::InboxLinkPreviewService.new(link: link).perform
    link.assign_attributes(meta_initial_messages_enabled: true, meta_initial_messages_limit: 5)
    service = Whatsapp::InboxLinkPreviewService.new(link: link)
    expect(service.confirmed?(previous[:confirmation], service.perform)).to be(false)
  end

  it 'requires an explicit primary and rejects cross-account partners' do
    put path, headers: headers, params: attributes.except(:primary_inbox_id), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    foreign = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
    put path, headers: headers, params: attributes.merge(partner_inbox_id: foreign.id), as: :json
    expect(response).to have_http_status(:not_found)
    expect(WhatsappInboxLink.count).to eq(0)
  end

  it 'enables without confirmation only when there are no existing active conversations, and DELETE disables' do
    put path, headers: headers, params: attributes.merge(enabled: true), as: :json
    expect(response).to have_http_status(:ok)
    link = WhatsappInboxLink.find(response.parsed_body.dig('link', 'id'))
    expect(link).to be_enabled
    expect(link.activated_at).to be_present
    delete path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(link.reload).not_to be_enabled
    expect(response.parsed_body.dig('link', 'activated_at')).to be_present
  end

  it 'previews conflicts, requires the unchanged preview token and never merges historical conversations', :aggregate_failures do
    contact = create(:contact, account: account)
    first = create(:conversation, account: account, inbox: uno, contact: contact, status: :open)
    second = create(:conversation, account: account, inbox: meta, contact: contact, status: :pending)
    params = attributes.merge(enabled: true)
    post "#{path}/preview", headers: headers, params: params, as: :json
    expect(response).to have_http_status(:ok)
    preview = response.parsed_body['preview']
    expect(preview['conflicts']).to eq([{ 'contact_id' => contact.id, 'conversation_ids' => [first.id, second.id],
                                          'resolution' => 'manual_review_required' }])
    expect(WhatsappInboxLink.count).to eq(0)
    put path, headers: headers, params: params.merge(confirmation: true), as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to eq('preview_confirmation_required')
    expect do
      put path, headers: headers, params: params.merge(confirmation: preview['confirmation']), as: :json
    end.not_to change(Conversation, :count)
    expect(response).to have_http_status(:ok)
    expect(first.reload.inbox_id).to eq(uno.id)
    expect(second.reload.inbox_id).to eq(meta.id)
  end

  it 'invalidates confirmation when the reviewed conversation or configuration changes' do
    conversation = create(:conversation, account: account, inbox: uno, status: :open)
    params = attributes.merge(enabled: true)
    post "#{path}/preview", headers: headers, params: params, as: :json
    token = response.parsed_body.dig('preview', 'confirmation')
    put path, headers: headers, params: params.merge(default_provider: 'unoapi', confirmation: token), as: :json
    expect(response).to have_http_status(:conflict)
    conversation.update!(status: :pending)
    put path, headers: headers, params: params.merge(confirmation: token), as: :json
    expect(response).to have_http_status(:conflict)
    expect(WhatsappInboxLink.count).to eq(0)
  end

  it 'rejects expired confirmation' do
    create(:conversation, account: account, inbox: uno)
    post "#{path}/preview", headers: headers, params: attributes.merge(enabled: true), as: :json
    token = response.parsed_body.dig('preview', 'confirmation')
    travel_to 16.minutes.from_now do
      put path, headers: headers, params: attributes.merge(enabled: true, confirmation: token), as: :json
      expect(response).to have_http_status(:conflict)
    end
  end

  it 'rejects a second enabled pairing in reverse order' do
    WhatsappInboxLink.create!(account: account, primary_inbox: uno, secondary_inbox: meta, default_provider: 'unoapi', enabled: true)
    other = create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                                      sync_templates: false, validate_provider_config: false).inbox
    put(
      "/api/v1/accounts/#{account.id}/inboxes/#{other.id}/whatsapp_link",
      headers: headers,
      params: { partner_inbox_id: meta.id, primary_inbox_id: meta.id, enabled: true }, as: :json
    )
    expect(response).to have_http_status(:unprocessable_entity)
    expect(WhatsappInboxLink.where(enabled: true).count).to eq(1)
  end

  it 'serializes transport options for an administrator without exposing provider credentials' do
    link = WhatsappInboxLink.create!(account: account, primary_inbox: uno, secondary_inbox: meta,
                                     default_provider: 'unoapi', enabled: true)
    conversation = create(:conversation, account: account, inbox: uno)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['whatsapp_transport_options']).to include('link_id' => link.id, 'primary_inbox_id' => uno.id)
    expect(response.parsed_body['whatsapp_transport_options'].to_json).not_to include('api_key', 'provider_config', 'test_key')
  end

  it 'shows both transports to a principal-only agent without granting access to secondary history or candidates' do
    link = WhatsappInboxLink.create!(account: account, primary_inbox: uno, secondary_inbox: meta,
                                     default_provider: 'unoapi', enabled: true)
    create(:inbox_member, inbox: uno, user: agent)
    conversation = create(:conversation, account: account, inbox: uno, assignee: agent)
    historical = create(:conversation, account: account, inbox: meta)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['whatsapp_transport_options']).to include('link_id' => link.id)
    expect(response.parsed_body.dig('whatsapp_transport_options', 'transports').pluck('inbox_id')).to eq([uno.id, meta.id])

    get "/api/v1/accounts/#{account.id}/conversations/#{historical.display_id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).not_to have_key('whatsapp_transport_options')

    get path, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).not_to have_key('candidates')
  end

  it 'omits options for a secondary-only agent viewing their historical conversation' do
    WhatsappInboxLink.create!(account: account, primary_inbox: uno, secondary_inbox: meta,
                              default_provider: 'unoapi', enabled: true)
    create(:inbox_member, inbox: meta, user: agent)
    historical = create(:conversation, account: account, inbox: meta, assignee: agent)
    get "/api/v1/accounts/#{account.id}/conversations/#{historical.display_id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).not_to have_key('whatsapp_transport_options')

    create(:inbox_member, inbox: uno, user: agent)
    get "/api/v1/accounts/#{account.id}/conversations/#{historical.display_id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to have_key('whatsapp_transport_options')
  end
end
