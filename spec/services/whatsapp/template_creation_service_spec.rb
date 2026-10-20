require 'rails_helper'

RSpec.describe Whatsapp::TemplateCreationService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).tap do |record|
      record.update!(provider_config: record.provider_config.merge('api_key' => 'synthetic-template-secret'))
    end
  end
  let(:attributes) { { name: 'order_update', language: 'pt_BR', category: 'UTILITY', body: 'Olá {{1}}', examples: ['Ana'] } }
  let(:definition) { Whatsapp::TemplateDefinition.new(attributes) }
  let(:service) { described_class.new(channel: channel, definition: definition) }
  let(:url) { "https://graph.facebook.com/#{Whatsapp::ApiVersion.current}/123456789/message_templates" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:logs) { [] }

  before do
    %i[debug info warn error].each { |level| allow(Rails.logger).to receive(level) { |*args| logs << args.inspect } }
  end

  it 'journals one POST, replays its accepted result and preserves named and existing cached templates' do
    previous = channel.message_templates.deep_dup
    timestamp = channel.reload.message_templates_last_updated
    request = stub_request(:post, url).with(headers: { 'Authorization' => 'Bearer synthetic-template-secret',
                                                       'Content-Type' => 'application/json' }, body: definition.payload.to_json)
                                      .to_return(status: 200, body: { id: '987' }.to_json, headers: json_headers)

    first = nil
    expect { first = service.perform }.to change(WhatsappTemplateRequest, :count).by(1)
    expect(first[:template]).to include('id' => '987', 'status' => 'PENDING', 'parameter_format' => 'POSITIONAL')
    expect(described_class.new(channel: channel.reload, definition: definition).perform).to eq(first)
    expect(request).to have_been_requested.once
    expect(WhatsappTemplateRequest.last).to have_attributes(state: 'accepted', provider_template_id: '987', account_id: channel.account_id)
    expect(channel.reload.message_templates).to eq(previous + [first[:template]])
    expect(channel.message_templates_last_updated).to eq(timestamp)
  end

  it 'never sends a WhatsApp message or logs a credential during template creation' do
    stub_request(:post, url).to_return(status: 200, body: { id: '987' }.to_json, headers: json_headers)

    expect { service.perform }.not_to change(Message, :count)

    expect(logs.join).not_to include('synthetic-template-secret')
    expect(WebMock).not_to have_requested(:post, %r{/messages(?:\?|$)})
  end

  it 'exposes only a bounded sanitized error_user_msg and safe code/subcode, not raw provider debug text' do
    message = "Revise synthetic-template-secret access_token=another-secret #{'x' * 600}"
    stub_request(:post, url).to_return(status: 400, headers: json_headers, body: {
      error: { code: 100, error_subcode: 2_388_092, message: 'raw-debug', error_user_msg: message, fbtrace_id: 'private-trace' }
    }.to_json)

    result = service.perform

    expect(result).to include(error: 'provider_rejected', provider_code: 100, provider_subcode: 2_388_092)
    expect(result[:provider_message]).to start_with('Revise')
    expect(result[:provider_message].length).to be <= 500
    expect(result.to_json).not_to include('synthetic-template-secret', 'another-secret', 'raw-debug', 'private-trace')
    expect(WhatsappTemplateRequest.last.result['provider_message']).to eq(result[:provider_message])
    expect(logs.join).not_to include('synthetic-template-secret', 'another-secret', 'raw-debug', 'private-trace')
  end

  it 'never falls back to raw message when error_user_msg is absent' do
    stub_request(:post, url).to_return(status: 400, headers: json_headers,
                                       body: { error: { code: 100, message: 'raw-debug synthetic-template-secret' } }.to_json)

    result = service.perform

    expect(result).to include(error: 'provider_rejected', provider_code: 100)
    expect(result).not_to have_key(:provider_message)
    expect(result.to_json).not_to include('raw-debug', 'synthetic-template-secret')
  end

  it 'replaces only the same name and language cache entry' do
    old = definition.payload.merge('id' => 'old', 'status' => 'REJECTED')
    other_language = old.merge('language' => 'en_US', 'id' => 'other-language')
    channel.update!(message_templates: [old, other_language])
    stub_request(:post, url).to_return(status: 200, body: { id: '987', status: 'PENDING' }.to_json, headers: json_headers)

    result = service.perform

    expect(channel.reload.message_templates).to eq([other_language, result[:template]])
  end

  [[10, 'permission_denied'], [200, 'permission_denied'], [190, 'authentication_required'], [100, 'provider_rejected']].each do |code, reason|
    it "maps provider code #{code} to #{reason} without leaking raw provider secrets" do
      previous = channel.message_templates.deep_dup
      stub_request(:post, url).to_return(status: 400, headers: json_headers,
                                         body: { error: { code: code, message: 'raw-debug synthetic-template-secret',
                                                          error_user_msg: 'Revise o modelo.', error_subcode: 2_388_092,
                                                          fbtrace_id: 'private-trace' } }.to_json)

      result = service.perform

      expect(result).to include(error: reason, provider_code: code)
      expect(result.to_json).not_to include('raw-debug', 'synthetic-template-secret', 'private-trace')
      expect(WhatsappTemplateRequest.last).to have_attributes(state: 'rejected')
      expect(WhatsappTemplateRequest.last.result.to_json).not_to include('raw-debug', 'synthetic-template-secret', 'private-trace')
      expect(channel.reload.message_templates).to eq(previous)
      expect(logs.join).not_to include('raw-debug', 'synthetic-template-secret', 'private-trace')
    end
  end

  it 'does not repeat an uncertain POST after a timeout or persist the exception message' do
    request = stub_request(:post, url).to_raise(Net::ReadTimeout.new('raw-debug synthetic-template-secret'))

    expect(service.perform).to include(error: 'outcome_unknown')
    expect(described_class.new(channel: channel.reload, definition: definition).perform).to include(error: 'outcome_unknown')
    expect(request).to have_been_requested.once
    expect(WhatsappTemplateRequest.last).to have_attributes(state: 'uncertain')
    expect(WhatsappTemplateRequest.last.result.to_json).not_to include('raw-debug', 'synthetic-template-secret')
    expect(logs.join).not_to include('raw-debug', 'synthetic-template-secret')
  end

  [[503, { error: { code: 2, message: 'raw-debug' } }], [200, []], [200, {}], [200, { id: 'invalid' }]].each do |status, body|
    it "blocks replay after an ambiguous response #{status}/#{body.inspect}" do
      request = stub_request(:post, url).to_return(status: status, body: body.to_json, headers: json_headers)

      expect(service.perform).to include(error: 'outcome_unknown')
      expect(described_class.new(channel: channel.reload, definition: definition).perform).to include(error: 'outcome_unknown')
      expect(request).to have_been_requested.once
      expect(WhatsappTemplateRequest.last.state).to eq('uncertain')
    end
  end

  it 'rejects a changed payload after the same name and language have been accepted' do
    request = stub_request(:post, url).to_return(status: 200, body: { id: '987' }.to_json, headers: json_headers)
    service.perform
    changed = Whatsapp::TemplateDefinition.new(attributes.merge(body: 'Outro texto {{1}}'))

    expect(described_class.new(channel: channel, definition: changed).perform).to eq(error: 'name_conflict')
    expect(request).to have_been_requested.once
    expect(WhatsappTemplateRequest.last.state).to eq('accepted')
  end

  it 'reconciles an uncertain request only after a matching template has been synced, ignoring example differences' do
    request = stub_request(:post, url).to_timeout
    service.perform
    synced = definition.payload.merge('id' => '987', 'status' => 'APPROVED')
    synced['components'].first['example'] = { 'body_text' => [['Outro exemplo']] }
    channel.update!(message_templates: channel.message_templates + [synced])

    expect(described_class.new(channel: channel, definition: definition).perform).to eq(template: synced)
    expect(WhatsappTemplateRequest.last).to have_attributes(state: 'accepted', provider_template_id: '987')
    expect(request).to have_been_requested.once
  end

  [{ 'name' => 'other_name' }, { 'language' => 'en_US' }, { 'id' => nil },
   { 'components' => [{ 'type' => 'BODY', 'text' => 'Different text' }] }].each do |mismatch|
    it "does not reconcile a cached template with mismatched identity or components #{mismatch.keys}" do
      request = stub_request(:post, url).to_timeout
      service.perform
      cached = definition.payload.merge('id' => '987', 'status' => 'APPROVED').merge(mismatch)
      channel.update!(message_templates: [cached])

      expect(described_class.new(channel: channel, definition: definition).perform).to include(error: 'outcome_unknown')
      expect(WhatsappTemplateRequest.last.state).to eq('uncertain')
      expect(request).to have_been_requested.once
    end
  end

  it 'allows an explicit retry after a definite provider rejection' do
    request = stub_request(:post, url).to_return(status: 400, body: { error: { code: 100 } }.to_json, headers: json_headers)
                                      .then.to_return(status: 200, body: { id: '987' }.to_json, headers: json_headers)

    expect(service.perform).to include(error: 'provider_rejected')
    expect(described_class.new(channel: channel, definition: definition).perform[:template]).to include('id' => '987')
    expect(request).to have_been_requested.twice
    expect(WhatsappTemplateRequest.count).to eq(1)
  end

  [{ 'business_account_id' => 'invalid' }, { 'api_key' => '' }].each do |config|
    it "rejects missing configuration #{config.keys} without reserving or sending a request" do
      channel.update!(provider_config: channel.provider_config.merge(config))

      expect { expect(service.perform).to eq(error: 'configuration_missing') }.not_to change(WhatsappTemplateRequest, :count)
      expect(WebMock).not_to have_requested(:post, url)
    end
  end
end
