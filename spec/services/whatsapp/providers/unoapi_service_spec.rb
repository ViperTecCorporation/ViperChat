require 'rails_helper'

describe Whatsapp::Providers::UnoapiService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      phone_number: "+1555#{SecureRandom.random_number(1_000_000_000).to_s.rjust(9, '0')}",
      provider: 'unoapi',
      provider_config: {
        'url' => 'https://uno.example.com',
        'api_key' => 'test_key',
        'business_account_id' => '556600000000'
      },
      sync_templates: false,
      validate_provider_config: false
    )
  end

  describe '#validate_provider_config?' do
    it 'registers a connecting session before validating its newly generated token' do
      whatsapp_channel.provider_config['connect'] = true
      setup_service = instance_double(Whatsapp::UnoapiWebhookSetupService, perform: true)
      allow(Whatsapp::UnoapiWebhookSetupService).to receive(:new).and_return(setup_service)

      expect(HTTParty).not_to receive(:get)
      expect(service.validate_provider_config?).to be(true)
      expect(setup_service).to have_received(:perform).with(whatsapp_channel)
    end
  end

  describe '#send_message' do
    let(:conversation) do
      create(:conversation, account: whatsapp_channel.account, inbox: whatsapp_channel.inbox)
    end
    let(:message) do
      create(
        :message,
        account: whatsapp_channel.account,
        inbox: whatsapp_channel.inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: 'Solicitação de pagamento PIX',
        content_attributes: { whatsapp_interactive: { type: 'payment_request' } }
      )
    end

    before do
      whatsapp_channel.update!(
        provider_config: whatsapp_channel.provider_config.merge(
          'phone_number_id' => 'random_id',
          'pix_merchant_name' => 'Minha Empresa',
          'pix_key' => 'financeiro@minhaempresa.com.br',
          'pix_key_type' => 'EMAIL'
        )
      )
    end

    it 'sends the configured PIX key as an UnoAPI payment request' do
      stub = stub_request(:post, 'https://uno.example.com/v13.0/random_id/messages')
             .with(
               headers: { 'Authorization' => 'Bearer test_key', 'Content-Type' => 'application/json' },
               body: {
                 messaging_product: 'whatsapp',
                 to: '5511912008012',
                 type: 'interactive',
                 interactive: {
                   type: 'button',
                   action: {
                     buttons: [{
                       type: 'payment_request',
                       payment_setting: {
                         type: 'pix_static_code',
                         pix_static_code: {
                           merchant_name: 'Minha Empresa',
                           key: 'financeiro@minhaempresa.com.br',
                           key_type: 'EMAIL'
                         }
                       }
                     }]
                   }
                 }
               }.to_json
             )
             .to_return(
               status: 200,
               body: { statuses: [{ id: 'uno-pix-message-id', status: 'sent' }] }.to_json,
               headers: { 'Content-Type' => 'application/json' }
             )

      expect(service.send_message('5511912008012', message)).to eq('uno-pix-message-id')
      expect(message.reload.status).to eq('sent')
      expect(stub).to have_been_requested.once
    end

    it 'accepts the standard messages response shape as a fallback' do
      stub_request(:post, 'https://uno.example.com/v13.0/random_id/messages')
        .to_return(
          status: 200,
          body: { messages: [{ id: 'uno-standard-message-id' }] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect(service.send_message('5511912008012', message)).to eq('uno-standard-message-id')
    end

    it 'quotes an interactive message without prefixing the agent name' do
      original_message = create(
        :message,
        account: whatsapp_channel.account,
        inbox: whatsapp_channel.inbox,
        conversation: conversation,
        message_type: :incoming,
        source_id: 'uno-interactive-source-id',
        content: 'Escolha uma opção'
      )
      reply_message = create(
        :message,
        account: whatsapp_channel.account,
        inbox: whatsapp_channel.inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: create(:user, account: whatsapp_channel.account, name: 'Rodrigo'),
        content: 'Básico',
        content_attributes: {
          in_reply_to: original_message.id,
          whatsapp_interactive_reply: { id: 'plan_basic', title: 'Básico', type: 'list_reply' }
        }
      )
      whatsapp_channel.update!(provider_config: whatsapp_channel.provider_config.merge('send_agent_name' => true))

      stub = stub_request(:post, 'https://uno.example.com/v13.0/random_id/messages')
             .with(
               body: {
                 messaging_product: 'whatsapp',
                 recipient_type: 'individual',
                 context: { message_id: 'uno-interactive-source-id' },
                 to: '5511912008012',
                 text: { body: 'Básico' },
                 type: 'text'
               }.to_json
             )
             .to_return(
               status: 200,
               body: { messages: [{ id: 'uno-interactive-reply-id' }] }.to_json,
               headers: { 'Content-Type' => 'application/json' }
             )

      expect(service.send_message('5511912008012', reply_message)).to eq('uno-interactive-reply-id')
      expect(stub).to have_been_requested.once
    end

    it 'marks the message failed when the configured PIX key is missing' do
      whatsapp_channel.update!(
        provider_config: whatsapp_channel.provider_config.except('pix_merchant_name', 'pix_key', 'pix_key_type')
      )

      expect(service.send_message('5511912008012', message)).to be_nil
      expect(message.reload).to have_attributes(
        status: 'failed',
        external_error: 'PIX payment configuration is incomplete for this inbox'
      )
    end

    it 'marks the message failed for group conversations' do
      conversation.update!(group: true)

      expect(service.send_message('120363040468224422@g.us', message)).to be_nil
      expect(message.reload).to have_attributes(
        status: 'failed',
        external_error: 'PIX payment requests are not supported in groups'
      )
    end
  end

  describe 'LID routing' do
    let(:contact) { create(:contact, account: whatsapp_channel.account, phone_number: '+5511912345678') }
    let(:contact_inbox) do
      create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: contact, source_id: '5511912345678')
    end
    let(:conversation) do
      create(
        :conversation,
        account: whatsapp_channel.account,
        inbox: whatsapp_channel.inbox,
        contact: contact,
        contact_inbox: contact_inbox
      )
    end
    let(:message) do
      create(
        :message,
        account: whatsapp_channel.account,
        inbox: whatsapp_channel.inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: 'Mensagem com LID'
      )
    end

    before do
      whatsapp_channel.update!(provider_config: whatsapp_channel.provider_config.merge('phone_number_id' => 'random_id'))
    end

    it 'keeps the phone in to and adds the canonical inbox LID' do
      create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: contact, source_id: '20173562093816:70@lid')
      stub = stub_request(:post, 'https://uno.example.com/v13.0/random_id/messages')
             .with do |request|
               payload = JSON.parse(request.body)
               payload['to'] == '5511912345678' && payload['user_id'] == '20173562093816@lid'
             end
             .to_return(status: 200, body: { messages: [{ id: 'lid-message-id' }] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      expect(service.send_message('5511912345678', message)).to eq('lid-message-id')
      expect(stub).to have_been_requested.once
    end

    it 'does not fabricate user_id when the inbox has no valid LID' do
      create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: contact, source_id: 'invalid@lid')
      stub = stub_request(:post, 'https://uno.example.com/v13.0/random_id/messages')
             .with { |request| JSON.parse(request.body).exclude?('user_id') }
             .to_return(status: 200, body: { messages: [{ id: 'phone-only-message-id' }] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      expect(service.send_message('5511912345678', message)).to eq('phone-only-message-id')
      expect(stub).to have_been_requested.once
    end

    it 'does not reuse a LID stored for the same contact in another inbox' do
      other_channel = create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
      create(:contact_inbox, inbox: other_channel.inbox, contact: contact, source_id: '998877665544@lid')
      stub = stub_request(:post, 'https://uno.example.com/v13.0/random_id/messages')
             .with { |request| JSON.parse(request.body).exclude?('user_id') }
             .to_return(status: 200, body: { messages: [{ id: 'isolated-message-id' }] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      expect(service.send_message('5511912345678', message)).to eq('isolated-message-id')
      expect(stub).to have_been_requested.once
    end

    it 'does not add an individual LID to group payloads' do
      create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: contact, source_id: '20173562093816@lid')
      conversation.update!(group: true, group_source_id: '120363040468224422@g.us')
      stub = stub_request(:post, 'https://uno.example.com/v13.0/random_id/messages')
             .with do |request|
               payload = JSON.parse(request.body)
               payload['recipient_type'] == 'group' && payload.exclude?('user_id')
             end
             .to_return(status: 200, body: { messages: [{ id: 'group-message-id' }] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      expect(service.send_message('120363040468224422@g.us', message)).to eq('group-message-id')
      expect(stub).to have_been_requested.once
    end

    describe 'outgoing identity composition' do
      def composed_payload(request_body = { to: '5511912345678', type: 'text' })
        service.send(:outgoing_message_payload, request_body, message)
      end

      it 'sends phone, canonical LID and normalized username together' do
        contact.update!(whatsapp_username: '@Contato.Exemplo')
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: contact, source_id: '20173562093816:70@lid')

        expect(composed_payload).to include(
          to: '5511912345678',
          user_id: '20173562093816@lid',
          username: 'contato.exemplo'
        )
      end

      it 'sends phone and username without fabricating a LID' do
        contact.update!(whatsapp_username: '@contato.exemplo')

        expect(composed_payload).to include(to: '5511912345678', username: 'contato.exemplo')
        expect(composed_payload).not_to have_key(:user_id)
      end

      it 'sends phone and LID without fabricating a username' do
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: contact, source_id: '20173562093816@lid')

        expect(composed_payload).to include(to: '5511912345678', user_id: '20173562093816@lid')
        expect(composed_payload).not_to have_key(:username)
      end

      it 'keeps a phone-only payload without extra identities' do
        expect(composed_payload).to include(to: '5511912345678')
        expect(composed_payload).not_to have_key(:user_id)
        expect(composed_payload).not_to have_key(:username)
      end

      it 'uses the canonical LID as to when no recipient or username is available' do
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: contact, source_id: '20173562093816:70@lid')

        expect(composed_payload(to: nil, type: 'text')).to include(
          to: '20173562093816@lid',
          user_id: '20173562093816@lid'
        )
      end

      it 'uses the normalized username as the final to fallback' do
        contact.update!(whatsapp_username: '  @Contato.Exemplo  ')

        expect(composed_payload(to: nil, type: 'text')).to include(
          to: 'contato.exemplo',
          username: 'contato.exemplo'
        )
      end

      it 'does not send a blank username' do
        contact.update!(whatsapp_username: '  ')

        expect(composed_payload(to: nil, type: 'text')).not_to have_key(:username)
      end

      it 'uses only the conversation contact username' do
        contact.update!(whatsapp_username: '@contato.correto')
        create(:contact, account: whatsapp_channel.account, whatsapp_username: '@outro.contato')

        expect(composed_payload).to include(username: 'contato.correto')
      end

      it 'preserves group payloads without individual identities' do
        contact.update!(whatsapp_username: '@contato.exemplo')
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: contact, source_id: '20173562093816@lid')
        conversation.update!(group: true, group_source_id: '120363040468224422@g.us')
        request_body = {
          messaging_product: 'whatsapp',
          recipient_type: 'group',
          to: '120363040468224422@g.us',
          type: 'text'
        }

        expect(composed_payload(request_body)).to eq(request_body)
      end

      it 'composes the same identities for text, media, interactive and PIX payloads' do
        contact.update!(whatsapp_username: '@contato.exemplo')
        create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: contact, source_id: '20173562093816@lid')

        payloads = [
          { to: '5511912345678', type: 'text' },
          { 'to' => '5511912345678', 'type' => 'image' },
          { to: '5511912345678', type: 'interactive' },
          { to: '5511912345678', type: 'interactive', interactive: { type: 'button' } }
        ]

        payloads.each do |request_body|
          payload = composed_payload(request_body)
          expect(payload.values_at(:user_id, :username)).to eq(['20173562093816@lid', 'contato.exemplo'])
          expect(JSON.parse(payload.to_json)['to']).to eq('5511912345678')
        end
      end
    end
  end

  it 'fetches group participants from the Uno v15 group endpoint' do
    stub = stub_request(:get, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/participants')
           .with(headers: { 'Authorization' => 'Bearer test_key', 'Content-Type' => 'application/json' })
           .to_return(status: 200, body: { participants: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.group_participants('120363040468224422@g.us')).to be_success
    expect(stub).to have_been_requested
  end

  it 'fetches group details from the Uno v15 group endpoint' do
    stub = stub_request(:get, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us')
           .with(headers: { 'Authorization' => 'Bearer test_key', 'Content-Type' => 'application/json' })
           .to_return(status: 200, body: { subject: 'Equipe Comercial' }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.group_details('120363040468224422@g.us')).to be_success
    expect(stub).to have_been_requested
  end

  it 'prefers phone_number_id as the Uno session id when present' do
    whatsapp_channel.provider_config['phone_number_id'] = '5566999554300'
    whatsapp_channel.provider_config['business_account_id'] = '154253852486255'
    stub = stub_request(:get, 'https://uno.example.com/v15.0/5566999554300/groups/120363040468224422%40g.us/participants')
           .to_return(status: 200, body: { participants: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.group_participants('120363040468224422@g.us')).to be_success
    expect(stub).to have_been_requested
  end

  it 'updates a group through the Uno v15 group endpoint' do
    stub = stub_request(:patch, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us')
           .with(
             body: {
               subject: 'Novo nome',
               description: 'Nova descricao',
               picture: { url: 'https://cdn.example.com/group.jpg' },
               announcement: true,
               locked: false,
               join_approval_mode: 'approval_required'
             }.to_json
           )
           .to_return(status: 200, body: { updated: true }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(
      service.update_group(
        group_id: '120363040468224422@g.us',
        subject: 'Novo nome',
        description: 'Nova descricao',
        picture_url: 'https://cdn.example.com/group.jpg',
        announcement: true,
        locked: false,
        join_approval_mode: 'approval_required'
      )
    ).to be_success
    expect(stub).to have_been_requested
  end

  it 'leaves a group through the Uno v15 group endpoint without a request body' do
    stub = stub_request(:delete, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us')
           .with { |request| request.body.blank? }
           .to_return(
             status: 200,
             body: { group_id: '120363040468224422@g.us', deleted: true }.to_json,
             headers: { 'Content-Type' => 'application/json' }
           )

    expect(service.leave_group('120363040468224422@g.us')).to be_success
    expect(stub).to have_been_requested
  end

  it 'fetches and resets group invite link through the Uno v15 group endpoint' do
    get_stub = stub_request(:get, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/invite_link')
               .to_return(
                 status: 200,
                 body: { invite_link: 'https://chat.whatsapp.com/old123' }.to_json,
                 headers: { 'Content-Type' => 'application/json' }
               )
    reset_stub = stub_request(:post, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/invite_link')
                 .to_return(
                   status: 200,
                   body: { invite_link: 'https://chat.whatsapp.com/new456' }.to_json,
                   headers: { 'Content-Type' => 'application/json' }
                 )

    expect(service.group_invite_link('120363040468224422@g.us')).to be_success
    expect(service.reset_group_invite_link('120363040468224422@g.us')).to be_success
    expect(get_stub).to have_been_requested
    expect(reset_stub).to have_been_requested
  end

  it 'adds and removes group participants through the Uno v15 group endpoint' do
    add_stub = stub_request(:post, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/participants')
               .with(body: { participants: [{ wa_id: '556699999999', user_id: '123456789012345@lid' }] }.to_json)
               .to_return(status: 200, body: { added: ['556699999999'], failed: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    remove_stub = stub_request(:delete, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/participants')
                  .with(body: { participants: [{ wa_id: '556699999999', user_id: '123456789012345@lid' }] }.to_json)
                  .to_return(status: 200, body: { removed: ['556699999999'], failed: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

    participants = [{ wa_id: '556699999999', user_id: '123456789012345@lid' }]
    expect(service.add_group_participants(group_id: '120363040468224422@g.us', participants: participants)).to be_success
    expect(service.remove_group_participants(group_id: '120363040468224422@g.us', participants: participants)).to be_success
    expect(add_stub).to have_been_requested
    expect(remove_stub).to have_been_requested
  end

  it 'promotes group participants through the Uno v15 participant endpoint' do
    participants = [{ user_id: '123456789012345@lid', wa_id: '556699999999' }]
    stub = stub_request(:patch, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/participants')
           .with(body: { action: 'promote', participants: participants }.to_json)
           .to_return(
             status: 200,
             body: {
               group_id: '120363040468224422@g.us',
               promoted: ['123456789012345@lid'],
               failed: []
             }.to_json,
             headers: { 'Content-Type' => 'application/json' }
           )

    response = service.update_group_participant_roles(
      group_id: '120363040468224422@g.us',
      action: 'promote',
      participants: participants
    )

    expect(response).to be_success
    expect(stub).to have_been_requested
  end

  it 'fetches group join requests from the Uno v15 group endpoint' do
    stub = stub_request(:get, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/join_requests')
           .with(headers: { 'Authorization' => 'Bearer test_key', 'Content-Type' => 'application/json' })
           .to_return(status: 200, body: { join_requests: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.group_join_requests('120363040468224422@g.us')).to be_success
    expect(stub).to have_been_requested
  end

  it 'approves group join requests through the Uno v15 group endpoint' do
    stub = stub_request(:post, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/join_requests')
           .with(body: { participants: ['5566999999999'] }.to_json)
           .to_return(status: 200, body: { approved: ['5566999999999'], failed: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.approve_group_join_requests(group_id: '120363040468224422@g.us', participants: ['5566999999999'])).to be_success
    expect(stub).to have_been_requested
  end

  it 'rejects group join requests through the Uno v15 group endpoint' do
    stub = stub_request(:delete, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/join_requests')
           .with(body: { participants: ['5566999999999'] }.to_json)
           .to_return(status: 200, body: { rejected: ['5566999999999'], failed: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.reject_group_join_requests(group_id: '120363040468224422@g.us', participants: ['5566999999999'])).to be_success
    expect(stub).to have_been_requested
  end
end
