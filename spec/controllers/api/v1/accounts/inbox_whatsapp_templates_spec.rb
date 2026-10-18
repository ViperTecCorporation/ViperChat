require 'rails_helper'

RSpec.describe 'Inbox WhatsApp templates API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).tap do |record|
      record.update!(provider_config: record.provider_config.merge('api_key' => 'synthetic-template-secret'))
    end
  end
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/whatsapp_templates" }
  let(:graph_url) { "https://graph.facebook.com/#{Whatsapp::ApiVersion.current}/123456789/message_templates" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:attributes) { { name: 'order_update', language: 'pt_BR', category: 'UTILITY', body: 'Olá {{1}}', examples: ['Ana'] } }
  let(:logs) { [] }

  before do
    %i[debug info warn error].each { |level| allow(Rails.logger).to receive(level) { |*args| logs << args.inspect } }
  end

  [[:get, ''], [:post, ''], [:post, '/sync']].each do |method, suffix|
    context "when requesting #{method.upcase} whatsapp_templates#{suffix}" do
      it 'requires authentication before any provider request' do
        public_send(method, "#{url}#{suffix}", params: { template: attributes }, as: :json)

        expect(response).to have_http_status(:unauthorized)
        expect(WebMock).not_to have_requested(:any, graph_url)
      end

      it 'denies an ordinary agent even when assigned to the inbox' do
        agent = create(:user, account: account, role: :agent)
        create(:inbox_member, user: agent, inbox: channel.inbox)

        public_send(method, "#{url}#{suffix}", headers: agent.create_new_auth_token, params: { template: attributes }, as: :json)

        expect(response).to have_http_status(:unauthorized)
        expect(WebMock).not_to have_requested(:any, graph_url)
      end

      it 'does not expose or operate on an inbox from a different account' do
        other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
        foreign_url = "/api/v1/accounts/#{account.id}/inboxes/#{other.inbox.id}/whatsapp_templates#{suffix}"

        public_send(method, foreign_url, headers: headers, params: { template: attributes }, as: :json)

        expect(response).to have_http_status(:not_found)
        expect(WebMock).not_to have_requested(:any, graph_url)
      end

      it 'rejects ViperConnect without changing its configuration or templates' do
        channel.update!(provider: 'unoapi')
        previous = channel.attributes.slice('provider_config', 'message_templates')

        public_send(method, "#{url}#{suffix}", headers: headers, params: { template: attributes }, as: :json)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to include('error' => 'unsupported_provider')
        expect(channel.reload.attributes.slice('provider_config', 'message_templates')).to eq(previous)
        expect(WebMock).not_to have_requested(:any, graph_url)
      end

      it 'rejects a non-WhatsApp inbox' do
        inbox = create(:inbox, account: account)
        public_send(method, "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_templates#{suffix}",
                    headers: headers, params: { template: attributes }, as: :json)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to include('error' => 'unsupported_provider')
        expect(WebMock).not_to have_requested(:any, graph_url)
      end
    end
  end

  describe 'GET cached templates' do
    it 'returns named and positional templates unchanged, with their last update timestamp and no credentials' do
      previous = channel.message_templates.deep_dup
      timestamp = channel.message_templates_last_updated

      get url, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['templates']).to eq(previous)
      expect(response.parsed_body['templates']).to include(include('parameter_format' => 'NAMED'))
      expect(Time.zone.parse(response.parsed_body['last_updated_at'])).to be_within(1.second).of(timestamp)
      expect(response.body).not_to include('synthetic-template-secret', 'api_key', 'provider_config')
      expect(WebMock).not_to have_requested(:any, graph_url)
    end

    it 'returns an empty list when no templates have been cached' do
      channel.update!(message_templates: nil, message_templates_last_updated: nil)

      get url, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('templates' => [], 'last_updated_at' => nil)
    end
  end

  describe 'POST create template' do
    it 'creates a pending template once across repeated POSTs without sending a message or logging a token' do
      previous = channel.message_templates.deep_dup
      request = stub_request(:post, graph_url).with(headers: { 'Authorization' => 'Bearer synthetic-template-secret' })
                                              .to_return(status: 200, body: { id: '987' }.to_json, headers: json_headers)
      first = nil

      expect do
        post url, headers: headers, params: { template: attributes }, as: :json
        expect(response).to have_http_status(:created)
        first = response.parsed_body
        post url, headers: headers, params: { template: attributes }, as: :json
      end.to change(WhatsappTemplateRequest, :count).by(1).and not_change(Message, :count)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to eq(first)
      expect(first['template']).to include('id' => '987', 'status' => 'PENDING', 'name' => 'order_update')
      expect(channel.reload.message_templates).to eq(previous + [first['template']])
      expect(request).to have_been_requested.once
    end

    it 'blocks an explicit retry after an uncertain timeout' do
      request = stub_request(:post, graph_url).to_timeout
      previous = channel.message_templates.deep_dup

      2.times do
        post url, headers: headers, params: { template: attributes }, as: :json
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body).to include('error' => 'outcome_unknown')
      end

      expect(request).to have_been_requested.once
      expect(WhatsappTemplateRequest.last.state).to eq('uncertain')
      expect(channel.reload.message_templates).to eq(previous)
    end

    it 'returns a conflict when an accepted name is reused with different content' do
      request = stub_request(:post, graph_url).to_return(status: 200, body: { id: '987' }.to_json, headers: json_headers)
      post url, headers: headers, params: { template: attributes }, as: :json
      expect(response).to have_http_status(:created)

      post url, headers: headers, params: { template: attributes.merge(body: 'Mudou {{1}}') }, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include('error' => 'name_conflict')
      expect(request).to have_been_requested.once
    end

    it 'rejects invalid definitions before journaling or external calls' do
      expect do
        post url, headers: headers, params: { template: attributes.merge(body: '{{name}}') }, as: :json
      end.not_to change(WhatsappTemplateRequest, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'validation_failed')
      expect(response.parsed_body['errors']).to include('body.invalid_variables')
      expect(WebMock).not_to have_requested(:post, graph_url)
    end

    it 'returns a stable validation error when the template parameter is missing' do
      post url, headers: headers, params: {}, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'validation_failed', 'errors' => ['template.required'])
      expect(WebMock).not_to have_requested(:post, graph_url)
    end

    it 'does not accept a client-supplied Graph token, components, or WABA override' do
      request = stub_request(:post, graph_url).with do |http_request|
        payload = JSON.parse(http_request.body)
        payload['components'] == [{ 'type' => 'BODY', 'text' => 'Olá {{1}}', 'example' => { 'body_text' => [['Ana']] } }] &&
          !payload.key?('api_key') && !payload.key?('business_account_id')
      end.to_return(status: 200, body: { id: '987' }.to_json, headers: json_headers)

      post url, headers: headers, params: { template: attributes.merge(api_key: 'client-override', business_account_id: '999',
                                                                       components: [{ type: 'IMAGE' }]) }, as: :json

      expect(response).to have_http_status(:created)
      expect(request).to have_been_requested.once
      expect(channel.reload.provider_config).to include('api_key' => 'synthetic-template-secret', 'business_account_id' => '123456789')
    end

    [[10, 'permission_denied'], [200, 'permission_denied'], [190, 'authentication_required'], [100, 'provider_rejected']].each do |code, reason|
      it "returns a safe actionable error for Meta code #{code}" do
        stub_request(:post, graph_url).to_return(status: 400, headers: json_headers,
                                                 body: { error: { code: code, message: 'raw-debug synthetic-template-secret',
                                                                  error_user_msg: 'Revise o modelo.', fbtrace_id: 'private-trace' } }.to_json)

        post url, headers: headers, params: { template: attributes }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => reason, 'provider_code' => code)
        expect(response.body).not_to include('raw-debug', 'synthetic-template-secret', 'private-trace')
        expect(logs.join).not_to include('raw-debug', 'synthetic-template-secret', 'private-trace')
      end
    end
  end

  describe 'POST synchronous sync' do
    it 'clears stale cached templates after a successful empty result' do
      expect(channel.message_templates).to be_present
      stub_request(:get, graph_url).with(query: { limit: '100' }).to_return(
        status: 200, headers: json_headers, body: { data: [] }.to_json
      )

      post "#{url}/sync", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['templates']).to eq([])
      expect(response.parsed_body['last_updated_at']).to be_present
      expect(channel.reload.message_templates).to eq([])
    end

    it 'preserves a pending creation accepted during a sync, including the equal-start-time boundary' do
      channel
      headers
      pending = nil
      creation = stub_request(:post, graph_url).to_return(status: 200, headers: json_headers, body: { id: '987' }.to_json)
      stub_request(:get, graph_url).with(query: { limit: '100' }).to_return do
        result = Whatsapp::TemplateCreationService.new(channel: channel.reload,
                                                       definition: Whatsapp::TemplateDefinition.new(attributes)).perform
        pending = result[:template]
        { status: 200, headers: json_headers, body: { data: [] }.to_json }
      end

      travel_to(Time.current.change(usec: 0)) do
        post "#{url}/sync", headers: headers, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(pending).to include('id' => '987', 'status' => 'PENDING')
      expect(response.parsed_body['templates']).to eq([pending])
      expect(channel.reload.message_templates).to eq([pending])
      expect(creation).to have_been_requested.once
    end

    it 'paginates on the configured Graph endpoint using header auth and preserves named templates unchanged' do
      named = channel.message_templates.find { |template| template['parameter_format'] == 'NAMED' }
      pending = { 'id' => '987', 'name' => 'new_template', 'language' => 'pt_BR', 'status' => 'PENDING',
                  'components' => [{ 'type' => 'BODY', 'text' => 'Recebido.' }] }
      first_page = stub_request(:get, graph_url).with(query: { limit: '100' },
                                                      headers: { 'Authorization' => 'Bearer synthetic-template-secret' })
                                                .to_return(status: 200, headers: json_headers, body: {
                                                  data: [named], paging: { next: 'https://attacker.example/steal?access_token=private',
                                                                           cursors: { after: 'cursor-2' } }
                                                }.to_json)
      second_page = stub_request(:get, graph_url).with(query: { limit: '100', after: 'cursor-2' },
                                                       headers: { 'Authorization' => 'Bearer synthetic-template-secret' })
                                                 .to_return(status: 200, headers: json_headers, body: { data: [pending] }.to_json)

      expect { post "#{url}/sync", headers: headers, as: :json }.not_to change(Message, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['templates']).to eq([named, pending])
      expect(Time.zone.parse(response.parsed_body['last_updated_at'])).to be_within(2.seconds).of(Time.current)
      expect(channel.reload.message_templates).to eq([named, pending])
      expect(first_page).to have_been_requested.once
      expect(second_page).to have_been_requested.once
    end

    it 'never follows provider pagination URLs, sends messages, or exposes credentials in logs and the response' do
      stub_request(:get, graph_url).with(query: { limit: '100' }).to_return(status: 200, headers: json_headers, body: {
        data: [], paging: { next: 'https://attacker.example/steal?access_token=private', cursors: { after: 'cursor-2' } }
      }.to_json)
      stub_request(:get, graph_url).with(query: { limit: '100', after: 'cursor-2' }).to_return(
        status: 200, headers: json_headers, body: { data: [] }.to_json
      )

      post "#{url}/sync", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(WebMock).not_to have_requested(:get, %r{https://attacker.example/})
      expect(WebMock).not_to have_requested(:post, %r{/messages(?:\?|$)})
      expect(response.body).not_to include('synthetic-template-secret', 'private')
      expect(logs.join).not_to include('synthetic-template-secret')
    end

    [[10, 'permission_denied'], [200, 'permission_denied'], [190, 'authentication_required'], [100, 'provider_rejected']].each do |code, reason|
      it "preserves the cache and timestamp on provider error #{code}" do
        previous = channel.reload.attributes.slice('message_templates', 'message_templates_last_updated')
        stub_request(:get, graph_url).with(query: { limit: '100' }).to_return(
          status: 400, headers: json_headers, body: { error: { code: code, message: 'raw-debug synthetic-template-secret',
                                                               error_user_msg: 'Revise a permissão.', fbtrace_id: 'private-trace' } }.to_json
        )

        post "#{url}/sync", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => reason, 'provider_code' => code)
        expect(response.body).not_to include('raw-debug', 'synthetic-template-secret', 'private-trace')
        expect(channel.reload.attributes.slice('message_templates', 'message_templates_last_updated')).to eq(previous)
        expect(logs.join).not_to include('raw-debug', 'synthetic-template-secret', 'private-trace')
      end
    end

    it 'does not replace the cache with a partial result when a later page times out' do
      previous = channel.reload.attributes.slice('message_templates', 'message_templates_last_updated')
      stub_request(:get, graph_url).with(query: { limit: '100' }).to_return(status: 200, headers: json_headers, body: {
        data: [{ id: 'partial' }], paging: { next: 'ignored', cursors: { after: 'cursor-2' } }
      }.to_json)
      stub_request(:get, graph_url).with(query: { limit: '100', after: 'cursor-2' }).to_timeout

      post "#{url}/sync", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'temporarily_unavailable')
      expect(channel.reload.attributes.slice('message_templates', 'message_templates_last_updated')).to eq(previous)
    end

    [{ data: 'invalid' }, { data: [nil] }, { data: [], paging: { next: 'ignored' } }].each do |body|
      it "rejects malformed data or pagination without discarding the cache #{body.inspect}" do
        previous = channel.message_templates.deep_dup
        stub_request(:get, graph_url).with(query: { limit: '100' }).to_return(status: 200, headers: json_headers, body: body.to_json)

        post "#{url}/sync", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'temporarily_unavailable')
        expect(channel.reload.message_templates).to eq(previous)
      end
    end
  end
end
