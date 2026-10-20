require 'rails_helper'

RSpec.describe 'WhatsApp unified inbox administrative reviews API', type: :request do
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
  let(:link) do
    WhatsappInboxLink.create!(account: account, primary_inbox: uno, secondary_inbox: meta, default_provider: 'unoapi', enabled: true)
  end
  let(:headers) { admin.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/inboxes/#{uno.id}/whatsapp_link/reviews" }
  let(:service) { double('unified review service') }
  let(:item) { { id: 'event-123', version: 'revision-1', kind: 'event', status: 'review' } }
  let(:listing) { { items: [item], meta: { page: 1, total: 1, total_pages: 1 } } }

  before do
    account.enable_features!('inbox_management')
    allow(Whatsapp::UnifiedReviewService).to receive(:new).and_return(service)
  end

  it 'requires authentication for listing and both actions' do
    get path
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/event-123/recheck", params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/event-123/acknowledge", params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Whatsapp::UnifiedReviewService).not_to have_received(:new)
  end

  it 'denies agents even when assigned to both inboxes' do
    link
    create(:inbox_member, inbox: uno, user: agent)
    create(:inbox_member, inbox: meta, user: agent)
    agent_headers = agent.create_new_auth_token
    get path, headers: agent_headers
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/event-123/recheck", headers: agent_headers, params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/event-123/acknowledge", headers: agent_headers, params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Whatsapp::UnifiedReviewService).not_to have_received(:new)
  end

  it 'requires the inbox management feature for every endpoint' do
    link
    account.disable_features!('inbox_management')
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/event-123/recheck", headers: headers, params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/event-123/acknowledge", headers: headers, params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Whatsapp::UnifiedReviewService).not_to have_received(:new)
  end

  it 'returns an empty list without a link and rejects actions without creating one' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('items' => [], 'meta' => { 'page' => 1, 'total' => 0, 'total_pages' => 0 })
    post "#{path}/event-123/recheck", headers: headers, params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{path}/event-123/acknowledge", headers: headers, params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(WhatsappInboxLink.count).to eq(0)
    expect(Whatsapp::UnifiedReviewService).not_to have_received(:new)
  end

  it 'delegates only the documented list filters with the account-scoped link and current actor' do
    link
    expect(service).to receive(:list).with(page: '2', kind: 'event', status: 'review').and_return(listing)
    get path, headers: headers, params: { page: 2, kind: 'event', status: 'review', contact_id: 99, link_id: 999 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(listing.deep_stringify_keys)
    expect(Whatsapp::UnifiedReviewService).to have_received(:new).with(link: link, actor: admin)
  end

  it 'permits inspection of a disabled link without reactivating it' do
    link.update!(enabled: false)
    expect(service).to receive(:list).with(page: nil, kind: nil, status: nil).and_return(listing)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(link.reload).not_to be_enabled
    expect(Whatsapp::UnifiedReviewService).to have_received(:new).with(link: link, actor: admin)
  end

  it 'resolves the same link when accessed through the secondary inbox' do
    link
    allow(service).to receive(:list).and_return(listing)
    get "/api/v1/accounts/#{account.id}/inboxes/#{meta.id}/whatsapp_link/reviews", headers: headers
    expect(response).to have_http_status(:ok)
    expect(Whatsapp::UnifiedReviewService).to have_received(:new).with(link: link, actor: admin)
  end

  it 'prefers the enabled link over a more recently updated disabled draft' do
    link
    draft = WhatsappInboxLink.create!(account: account, primary_inbox: uno, secondary_inbox: meta,
                                     default_provider: 'unoapi', enabled: false)
    draft.update_columns(updated_at: 1.minute.from_now)
    allow(service).to receive(:list).and_return(listing)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(Whatsapp::UnifiedReviewService).to have_received(:new).with(link: link, actor: admin)
  end

  it 'selects the latest disabled link when no enabled link exists' do
    link.update!(enabled: false)
    latest = WhatsappInboxLink.create!(account: account, primary_inbox: uno, secondary_inbox: meta,
                                      default_provider: 'unoapi', enabled: false)
    latest.update_columns(updated_at: 1.minute.from_now)
    allow(service).to receive(:list).and_return(listing)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(Whatsapp::UnifiedReviewService).to have_received(:new).with(link: latest, actor: admin)
  end

  it 'delegates a disabled-link acknowledgement without changing link activation' do
    link.update!(enabled: false)
    cutoff = link.activated_at
    expect(service).to receive(:act).with(id: 'event-123', action: 'acknowledge', version: 'revision-1').and_return(item)
    post "#{path}/event-123/acknowledge", headers: headers, params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('item' => item.deep_stringify_keys)
    expect(link.reload).not_to be_enabled
    expect(link.activated_at).to eq(cutoff)
  end

  it 'requires update authorization on both pair inboxes, not only the requested inbox' do
    link
    allow_any_instance_of(InboxPolicy).to receive(:update?).and_wrap_original do |method|
      method.receiver.record.id != meta.id && method.call
    end
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(Whatsapp::UnifiedReviewService).not_to have_received(:new)
  end

  it 'does not resolve a foreign account inbox through the current account' do
    foreign = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false).inbox
    foreign_path = "/api/v1/accounts/#{account.id}/inboxes/#{foreign.id}/whatsapp_link/reviews"
    get foreign_path, headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{foreign_path}/event-123/recheck", headers: headers, params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{foreign_path}/event-123/acknowledge", headers: headers, params: { version: 'revision-1' }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(Whatsapp::UnifiedReviewService).not_to have_received(:new)
  end

  it 'denies access to another account even with a valid administrator token' do
    other_account = create(:account)
    get "/api/v1/accounts/#{other_account.id}/inboxes/#{uno.id}/whatsapp_link/reviews", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(Whatsapp::UnifiedReviewService).not_to have_received(:new)
  end

  %w[event-123 delivery-123 media-123 reservation-123].each do |review_id|
    %w[recheck acknowledge].each do |review_action|
      it "delegates #{review_action} for #{review_id} without accepting manual identity or send parameters" do
        link
        expect(service).to receive(:act).with(id: review_id, action: review_action, version: 'revision-1').and_return(item)
        post "#{path}/#{review_id}/#{review_action}", headers: headers, as: :json,
                                                      params: { version: 'revision-1', contact_id: 99, provider_message_id: 'manual', send: true }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('item' => item.deep_stringify_keys)
        expect(Whatsapp::UnifiedReviewService).to have_received(:new).with(link: link, actor: admin)
      end
    end
  end

  %w[recheck acknowledge].each do |review_action|
    [nil, '', {}, [], true].each do |invalid_version|
      it "rejects #{review_action} with invalid version #{invalid_version.inspect}" do
        link
        post "#{path}/event-123/#{review_action}", headers: headers, params: { version: invalid_version }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'invalid_review_request')
        expect(Whatsapp::UnifiedReviewService).not_to have_received(:new)
      end
    end

    it "maps stale #{review_action} versions to a conflict" do
      link
      allow(service).to receive(:act).and_raise(Whatsapp::UnifiedReviewService::Conflict)
      post "#{path}/event-123/#{review_action}", headers: headers, params: { version: 'old-revision' }, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'review_changed')
    end

    it "does not reveal a missing or foreign item on #{review_action}" do
      link
      allow(service).to receive(:act).and_raise(ActiveRecord::RecordNotFound)
      post "#{path}/event-999/#{review_action}", headers: headers, params: { version: 'revision-1' }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "maps unsupported #{review_action} requests to a safe validation error" do
      link
      allow(service).to receive(:act).and_raise(ArgumentError, 'sensitive internal context')
      post "#{path}/bad-id/#{review_action}", headers: headers, params: { version: 'revision-1' }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'invalid_review_request')
    end
  end

  it 'maps invalid list filters to a safe validation error' do
    link
    allow(service).to receive(:list).and_raise(ArgumentError, 'sensitive internal context')
    get path, headers: headers, params: { kind: 'unsupported' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_review_request')
  end
end

RSpec.describe 'WhatsApp unified inbox reviews with the real domain service', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5565987654321',
                             sync_templates: false, validate_provider_config: false)
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556587654321',
                             sync_templates: false, validate_provider_config: false)
  end
  let(:link) do
    WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox,
                             default_provider: 'unoapi', enabled: true)
  end
  let(:identity) do
    WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta, provider: 'whatsapp_cloud',
                                    external_id: 'wamid.admin-review-fixture', provider_message_id: 'original-admin-review-fixture')
  end
  let!(:event) do
    WhatsappUnifiedEvent.create!(whatsapp_inbox_link: link, whatsapp_message_identity: identity,
                                activation_cutoff: link.activated_at, state: 'review', reason: 'identity_pending', attempts: 12,
                                payload: { messages: [{ text: { body: 'private fixture message body' } }], token: 'fixture-secret-token' })
  end
  let(:headers) { admin.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/inboxes/#{uno.inbox.id}/whatsapp_link/reviews" }

  before { account.enable_features!('inbox_management') }

  it 'lists a reservation without a canonical message as acknowledgement-only and never reprocesses it' do
    reservation = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, original_id: 'reservation-admin-review-fixture',
                                                direction: 'incoming', participant_key: '5565987654321',
                                                message_kind: 'text', state: 'review')
    get path, headers: headers, params: { kind: 'reservation' }
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('items').sole
    expect(row).to include('id' => "reservation-#{reservation.id}", 'message_id' => nil, 'state' => 'review',
                           'actions' => { 'recheck' => false, 'acknowledge' => true })
    original = reservation.reload.attributes
    clear_enqueued_jobs
    post "#{path}/#{row.fetch('id')}/recheck", headers: headers, params: { version: row.fetch('version') }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(WhatsappUnifiedReviewAction.count).to eq(0)
    post "#{path}/#{row.fetch('id')}/acknowledge", headers: headers, params: { version: row.fetch('version') }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('reviewed_by_id' => admin.id, 'message_id' => nil)
    expect(WhatsappUnifiedReviewAction.last).to have_attributes(subject_kind: 'reservation', subject_id: reservation.id,
                                                               action: 'acknowledge', actor_id: admin.id)
    expect(reservation.reload.attributes).to eq(original)
    expect(enqueued_jobs).to be_empty
    expect(account.messages.count).to eq(0)
  end

  it 'serializes real review metadata without raw webhook content or secrets' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include(
      'id' => "event-#{event.id}", 'kind' => 'event', 'state' => 'review', 'reason' => 'identity_pending',
      'public_id' => identity.external_id, 'original_id' => identity.provider_message_id, 'attempts' => 12,
      'actions' => { 'recheck' => true, 'acknowledge' => true }
    )
    expect(response.parsed_body.fetch('meta')).to eq('page' => 1, 'total' => 1, 'total_pages' => 1)
    expect(response.body).not_to include('private fixture message body', 'fixture-secret-token', 'payload', 'provider_config', 'api_key')
  end

  it 'persists an acknowledgement audit without changing event quarantine or sending messages' do
    get path, headers: headers
    row = response.parsed_body.fetch('items').sole
    original = event.reload.attributes
    clear_enqueued_jobs
    expect do
      post "#{path}/#{row.fetch('id')}/acknowledge", headers: headers, params: { version: row.fetch('version') }, as: :json
    end.to change(WhatsappUnifiedReviewAction, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('reviewed_by_id' => admin.id, 'state' => 'review')
    expect(event.reload.attributes).to eq(original)
    expect(WhatsappUnifiedReviewAction.last).to have_attributes(
      whatsapp_inbox_link_id: link.id, actor_id: admin.id, subject_kind: 'event', subject_id: event.id,
      subject_updated_at: event.updated_at, action: 'acknowledge'
    )
    expect(enqueued_jobs).to be_empty
    expect(account.messages.count).to eq(0)
    expect(account.contacts.count).to eq(0)
    get path, headers: headers
    expect(response.parsed_body.fetch('items')).to be_empty
    get path, headers: headers, params: { status: 'acknowledged' }
    expect(response.parsed_body.fetch('items').sole.fetch('id')).to eq(row.fetch('id'))
  end

  it 'rejects a repeated stale acknowledgement without adding another audit entry' do
    get path, headers: headers
    row = response.parsed_body.fetch('items').sole
    post "#{path}/#{row.fetch('id')}/acknowledge", headers: headers, params: { version: row.fetch('version') }, as: :json
    expect(response).to have_http_status(:ok)
    expect do
      post "#{path}/#{row.fetch('id')}/acknowledge", headers: headers, params: { version: row.fetch('version') }, as: :json
    end.not_to change(WhatsappUnifiedReviewAction, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq('error' => 'review_changed')
    expect(event.reload.state).to eq('review')
  end

  it 'schedules only evidence re-evaluation on recheck and leaves provider delivery asynchronous' do
    get path, headers: headers
    row = response.parsed_body.fetch('items').sole
    clear_enqueued_jobs
    expect do
      post "#{path}/#{row.fetch('id')}/recheck", headers: headers, params: { version: row.fetch('version') }, as: :json
    end.to have_enqueued_job(Whatsapp::ProcessUnifiedEventJob).with(event.id)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('state' => 'pending', 'attempts' => 0)
    expect(enqueued_jobs.size).to eq(1)
    expect(WhatsappUnifiedReviewAction.last).to have_attributes(action: 'recheck', actor_id: admin.id, subject_id: event.id)
    expect(event.reload).to have_attributes(state: 'pending', attempts: 0)
    expect(account.messages.count).to eq(0)
    expect(account.contacts.count).to eq(0)
  end

  it 'keeps disabled-link evidence visible but prevents its reprocessing' do
    link.update!(enabled: false)
    get path, headers: headers
    row = response.parsed_body.fetch('items').sole
    expect(row.fetch('actions')).to include('recheck' => false)
    original = event.reload.attributes
    clear_enqueued_jobs
    expect do
      post "#{path}/#{row.fetch('id')}/recheck", headers: headers, params: { version: row.fetch('version') }, as: :json
    end.not_to change(WhatsappUnifiedReviewAction, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq('error' => 'review_changed')
    expect(event.reload.attributes).to eq(original)
    expect(link.reload).not_to be_enabled
    expect(enqueued_jobs).to be_empty
  end

  it 'rejects a version fetched before link deactivation' do
    get path, headers: headers
    row = response.parsed_body.fetch('items').sole
    link.update!(enabled: false)
    post "#{path}/#{row.fetch('id')}/recheck", headers: headers, params: { version: row.fetch('version') }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq('error' => 'review_changed')
    expect(event.reload.state).to eq('review')
  end
end
