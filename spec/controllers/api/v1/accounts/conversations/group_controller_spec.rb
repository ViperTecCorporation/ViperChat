require 'rails_helper'

RSpec.describe 'Conversation Group API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      account: account,
      phone_number: "+1555#{SecureRandom.random_number(1_000_000_000).to_s.rjust(9, '0')}",
      provider: 'unoapi',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: whatsapp_channel.inbox,
      group: true,
      group_source_id: '120363040468224422@g.us',
      group_session_admin: session_admin
    )
  end
  let(:session_admin) { true }
  let(:provider_service) { instance_double(Whatsapp::Providers::UnoapiService) }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/group" }

  before do
    create(:inbox_member, inbox: whatsapp_channel.inbox, user: agent)
    allow(Whatsapp::Providers::UnoapiService).to receive(:new).and_return(provider_service)
    allow(provider_service).to receive(:update_group)
    allow(provider_service).to receive(:leave_group)
  end

  it 'updates and persists all group permissions when the session is an admin' do
    provider_response = instance_double(HTTParty::Response, success?: true)
    allow(provider_service).to receive(:update_group).and_return(provider_response)

    patch path,
          params: {
            announcement: true,
            locked: false,
            join_approval_mode: 'approval_required'
          },
          headers: agent.create_new_auth_token,
          as: :json

    expect(response).to have_http_status(:ok)
    expect(provider_service).to have_received(:update_group).with(
      group_id: conversation.group_source_id,
      subject: nil,
      description: nil,
      picture_url: nil,
      announcement: true,
      locked: false,
      join_approval_mode: 'approval_required'
    )

    conversation.reload
    expect(conversation.group_join_approval_mode).to eq('approval_required')
    expect(conversation.additional_attributes['group_announcement']).to be(true)
    expect(conversation.additional_attributes['group_locked']).to be(false)
    expect(response.parsed_body).to include(
      'group_announcement' => true,
      'group_locked' => false,
      'group_join_approval_mode' => 'approval_required'
    )
  end

  it 'preserves a provider 404 and its validation error without changing local state' do
    provider_response = instance_double(
      HTTParty::Response,
      success?: false,
      code: 404,
      parsed_response: { 'error' => 'no supported group changes provided' }
    )
    allow(provider_service).to receive(:update_group).and_return(provider_response)

    patch path,
          params: { announcement: true },
          headers: agent.create_new_auth_token,
          as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('no supported group changes provided')
    expect(conversation.reload.additional_attributes['group_announcement']).to be_nil
  end

  context 'when the connected session is not a group admin' do
    let(:session_admin) { false }

    it 'rejects permission changes before calling the provider' do
      patch path,
            params: { announcement: true },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('Connected session must be a group admin')
      expect(provider_service).not_to have_received(:update_group)
    end

    it 'allows the session to leave the group' do
      provider_response = instance_double(HTTParty::Response, success?: true)
      allow(provider_service).to receive(:leave_group).and_return(provider_response)

      delete path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(provider_service).to have_received(:leave_group).with(conversation.group_source_id)

      conversation.reload
      expect(conversation.group_session_admin).to be(false)
      expect(conversation.additional_attributes['group_session_removed_at']).to be_present
      expect(conversation.messages.activity.last.content).to eq(
        I18n.t('conversations.activity.whatsapp.group_session_removed')
      )
    end

    it 'queues local conversation and attachment deletion only after the provider confirms leaving' do
      provider_response = instance_double(HTTParty::Response, success?: true)
      allow(provider_service).to receive(:leave_group).and_return(provider_response)

      expect do
        delete path,
               params: { delete_conversation: true },
               headers: agent.create_new_auth_token,
               as: :json
      end.to have_enqueued_job(Conversations::DeleteWithAttachmentsJob).with(conversation, agent, '127.0.0.1')

      expect(response).to have_http_status(:ok)
    end

    it 'preserves the local conversation when leaving fails' do
      provider_response = instance_double(
        HTTParty::Response,
        success?: false,
        code: 500,
        parsed_response: { 'error' => 'provider rejected leave' }
      )
      allow(provider_service).to receive(:leave_group).and_return(provider_response)

      expect do
        delete path,
               params: { delete_conversation: true },
               headers: agent.create_new_auth_token,
               as: :json
      end.not_to have_enqueued_job(Conversations::DeleteWithAttachmentsJob)

      expect(response).to have_http_status(:internal_server_error)
      expect(conversation.reload.additional_attributes['group_session_removed_at']).to be_nil
    end
  end

  it 'queues deletion after a status sync confirms that a timed-out leave succeeded' do
    sync_service = instance_double(Whatsapp::Unoapi::GroupParticipantsSyncService)
    allow(Whatsapp::Unoapi::GroupParticipantsSyncService).to receive(:new).and_return(sync_service)
    allow(sync_service).to receive(:perform) do
      conversation.update!(
        additional_attributes: conversation.additional_attributes.to_h.merge(
          'group_session_removed_at' => Time.current.iso8601
        )
      )
      :ok
    end

    expect do
      post "#{path}/sync",
           params: { delete_conversation: true },
           headers: agent.create_new_auth_token,
           as: :json
    end.to have_enqueued_job(Conversations::DeleteWithAttachmentsJob).with(conversation, agent, '127.0.0.1')

    expect(response).to have_http_status(:ok)
  end
end
