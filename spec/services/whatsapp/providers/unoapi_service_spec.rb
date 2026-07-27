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
                           merchant_name: whatsapp_channel.inbox.name,
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

    it 'marks the message failed when the configured PIX key is missing' do
      whatsapp_channel.update!(
        provider_config: whatsapp_channel.provider_config.except('pix_key', 'pix_key_type')
      )

      expect(service.send_message('5511912008012', message)).to be_nil
      expect(message.reload).to have_attributes(
        status: 'failed',
        external_error: 'PIX key is not configured for this inbox'
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
