require 'rails_helper'

RSpec.describe 'Scheduled Messages API', type: :request do
  let!(:account) { create(:account) }
  let!(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'unoapi',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let!(:contact) { create(:contact, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: channel.inbox) }
  let!(:conversation) do
    create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let!(:label) { create(:label, account: account) }
  let!(:agent) { create(:user, account: account) }
  let(:audio_blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('audio data'),
      filename: 'voice.mp3',
      content_type: 'audio/mpeg'
    )
  end
  let(:messages) do
    [
      { content: 'First', content_type: 'text', attachment_blob_ids: [] },
      { content: nil, content_type: 'text', voice_message: true, attachment_blob_ids: [audio_blob.signed_id] },
      { content: 'Third', content_type: 'text', attachment_blob_ids: [] }
    ]
  end
  let(:params) do
    {
      conversation_id: conversation.display_id,
      scheduled_message: {
        scheduled_at: 1.hour.from_now.iso8601,
        label_id: label.id,
        sender_id: agent.id,
        messages: messages
      }
    }
  end

  before do
    create(:inbox_member, inbox: channel.inbox, user: agent)
  end

  it 'creates one schedule containing an ordered message sequence' do
    expect do
      post "/api/v1/accounts/#{account.id}/scheduled_messages",
           params: params,
           headers: agent.create_new_auth_token,
           as: :json
    end.to change(ScheduledMessage, :count).by(1).and change(ScheduledMessageItem, :count).by(3)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['message_count']).to eq(3)
    expect(response.parsed_body['messages'].pluck('content')).to eq(['First', nil, 'Third'])
    expect(response.parsed_body['messages'][1]['voice_message']).to be(true)
    expect(response.parsed_body['messages'][1]['attachments']).to contain_exactly(
      include(
        'signed_id' => audio_blob.signed_id,
        'name' => 'voice.mp3',
        'content_type' => 'audio/mpeg',
        'url' => include('/rails/active_storage/blobs/redirect/')
      )
    )
  end

  it 'rejects a sequence with more than five messages' do
    params[:scheduled_message][:messages] = Array.new(6) { |index| { content: "Message #{index}", content_type: 'text' } }

    expect do
      post "/api/v1/accounts/#{account.id}/scheduled_messages",
           params: params,
           headers: agent.create_new_auth_token,
           as: :json
    end.not_to change(ScheduledMessage, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects scheduling in a conversation the agent cannot access' do
    restricted_agent = create(:user, account: account)
    params[:scheduled_message][:sender_id] = restricted_agent.id

    post "/api/v1/accounts/#{account.id}/scheduled_messages",
         params: params,
         headers: restricted_agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  context 'with transport selection' do
    let(:messages) { [{ content: 'Scheduled text', content_type: 'text' }] }
    let(:meta) do
      create(
        :channel_whatsapp,
        account: account, provider: 'whatsapp_cloud', phone_number: channel.phone_number.delete_prefix('+'),
        sync_templates: false, validate_provider_config: false
      ).inbox
    end
    let(:link) do
      WhatsappInboxLink.create!(
        account: account, primary_inbox: channel.inbox, secondary_inbox: meta, default_provider: 'whatsapp_cloud', enabled: true
      )
    end

    before do
      channel.update!(phone_number: '+5566996222471')
    end

    it 'keeps the unlinked legacy endpoint behavior and empty transport metadata' do
      post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['whatsapp_transport']).to eq({})
      expect(response.parsed_body['whatsapp_transport_options']).to be_nil
      expect(ScheduledMessage.last.items.first.whatsapp_transport).to eq({})
    end

    it 'captures the selected provider in both the root and items without trusting a client snapshot' do
      link
      params[:scheduled_message][:whatsapp_transport] = 'unoapi'
      post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      schedule = ScheduledMessage.last
      expect(schedule.whatsapp_transport).to include('requested_provider' => 'unoapi')
      expect(schedule.items.first.whatsapp_transport).to include('requested_provider' => 'unoapi')
      expect(response.parsed_body['whatsapp_transport']).to eq(schedule.whatsapp_transport)
      expect(response.parsed_body['messages'].first['whatsapp_transport']).to eq(schedule.items.first.whatsapp_transport)
      expect(response.parsed_body['whatsapp_transport_options']).to include('link_id' => link.id)
    end

    it 'captures the original inbox provider for an old app rather than the link default' do
      link
      post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(ScheduledMessage.last.whatsapp_transport).to include('requested_provider' => 'unoapi', 'selection_source' => 'legacy_inbox')
    end

    it 'captures an explicit Meta choice rather than the original inbox provider' do
      link
      params[:scheduled_message][:whatsapp_transport] = 'whatsapp_cloud'
      post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(ScheduledMessage.last.whatsapp_transport).to include('requested_provider' => 'whatsapp_cloud', 'selection_source' => 'explicit')
      expect(ScheduledMessage.last.items.first.whatsapp_transport).to include('provider' => 'whatsapp_cloud')
    end

    it 'preserves the existing snapshot on an old app update without a transport field' do
      link
      params[:scheduled_message][:whatsapp_transport] = 'unoapi'
      post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      schedule = ScheduledMessage.last
      snapshot = schedule.whatsapp_transport.deep_dup
      item_snapshot = schedule.items.first.whatsapp_transport.deep_dup
      link.update!(default_provider: 'unoapi')

      patch "/api/v1/accounts/#{account.id}/scheduled_messages/#{schedule.id}",
            params: { scheduled_message: { reason: 'Updated by old app' } }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.whatsapp_transport).to eq(snapshot)
      expect(schedule.items.first.reload.whatsapp_transport).to eq(item_snapshot)
    end

    it 'preserves the snapshot for replacement items when the transport field is omitted' do
      link
      params[:scheduled_message][:whatsapp_transport] = 'unoapi'
      post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      schedule = ScheduledMessage.last
      snapshot = schedule.whatsapp_transport.deep_dup
      item_snapshot = schedule.items.first.whatsapp_transport.deep_dup

      patch "/api/v1/accounts/#{account.id}/scheduled_messages/#{schedule.id}",
            params: { scheduled_message: { messages: [{ content: 'Replacement' }] } }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.whatsapp_transport).to eq(snapshot)
      expect(schedule.items.reload.first.whatsapp_transport).to eq(item_snapshot)
    end

    it 'does not erase dispatch evidence by replacing a linked sequence' do
      link
      params[:scheduled_message][:whatsapp_transport] = 'unoapi'
      post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      schedule = ScheduledMessage.last
      item = schedule.items.first
      item.update!(dispatched_at: Time.current)

      patch "/api/v1/accounts/#{account.id}/scheduled_messages/#{schedule.id}",
            params: { scheduled_message: { reason: 'Must roll back', messages: [{ content: 'Unsafe replacement' }] } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(schedule.reload.reason).to be_nil
      expect(schedule.items.reload.pluck(:id)).to eq([item.id])
      expect(item.reload.dispatched_at).to be_present
    end

    it 'rejects forged transport metadata during update without changing the schedule' do
      post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      schedule = ScheduledMessage.last

      patch "/api/v1/accounts/#{account.id}/scheduled_messages/#{schedule.id}",
            params: { scheduled_message: { reason: 'Must not save', whatsapp_transport: { provider: 'unoapi', link_id: 999 } } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(schedule.reload.reason).to be_nil
      expect(schedule.whatsapp_transport).to eq({})
    end

    [:dispatching, :sent].each do |item_status|
      it "does not reset a failed linked schedule with a #{item_status} item even without dispatch identifiers" do
        link
        params[:scheduled_message][:whatsapp_transport] = 'unoapi'
        post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:created)
        schedule = ScheduledMessage.last
        schedule.update!(status: :failed, error_message: 'Uncertain delivery')
        item = schedule.items.first
        item.update!(status: item_status)

        patch "/api/v1/accounts/#{account.id}/scheduled_messages/#{schedule.id}",
              params: { scheduled_message: { scheduled_at: 2.hours.from_now.iso8601 } }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(schedule.reload).to be_failed
        expect(schedule.error_message).to eq('Uncertain delivery')
        expect(schedule.items.reload.pluck(:id)).to eq([item.id])
        expect(item.reload.status).to eq(item_status.to_s)
      end
    end

    ['unknown', '', nil, { provider: 'unoapi', link_id: 123 }, ['unoapi']].each do |value|
      it "rejects an invalid explicit transport #{value.inspect} atomically" do
        params[:scheduled_message][:whatsapp_transport] = value

        expect do
          post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json
        end.not_to change(ScheduledMessage, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('whatsapp_transport must be unoapi or whatsapp_cloud')
      end
    end

    it 'shows the inferred old inbox intent without saving it during GET' do
      post "/api/v1/accounts/#{account.id}/scheduled_messages", params: params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      schedule = ScheduledMessage.last
      link

      get "/api/v1/accounts/#{account.id}/scheduled_messages",
          params: { date: schedule.scheduled_at.to_date.to_s }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.find { |item| item['id'] == schedule.id }['whatsapp_transport']).to eq(
        'requested_provider' => 'unoapi', 'selection_source' => 'legacy_inbox', 'pending_capture' => true
      )
      expect(schedule.reload.whatsapp_transport).to eq({})
      expect(schedule.items.first.whatsapp_transport).to eq({})
    end
  end
end
