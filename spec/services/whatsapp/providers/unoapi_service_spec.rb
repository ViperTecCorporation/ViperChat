require 'rails_helper'

describe Whatsapp::Providers::UnoapiService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:whatsapp_channel) do
    create(
      :channel_whatsapp,
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

  it 'fetches group participants from the Uno v15 group endpoint' do
    stub = stub_request(:get, 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/participants')
           .with(headers: { 'Authorization' => 'Bearer test_key', 'Content-Type' => 'application/json' })
           .to_return(status: 200, body: { participants: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.group_participants('120363040468224422@g.us')).to be_success
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
