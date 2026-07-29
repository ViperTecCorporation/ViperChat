require 'rails_helper'

describe Whatsapp::Unoapi::ContactSync::Client do
  subject(:client) { described_class.new(channel) }

  let(:channel) do
    create(
      :channel_whatsapp,
      phone_number: '+5566996222471',
      provider: 'unoapi',
      provider_config: {
        'url' => 'https://uno.example.com/',
        'api_key' => 'secret',
        'phone_number_id' => '5566996222471',
        'business_account_id' => '5566996222471'
      },
      sync_templates: false,
      validate_provider_config: false
    )
  end

  it 'finds the configured session and confirms it is online' do
    stub_request(:get, 'https://uno.example.com/sessions')
      .with(headers: { 'Authorization' => 'secret' })
      .to_return(
        status: 200,
        body: { data: [{ phone: '5566996222471', status: 'online' }] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    expect(client.session_online?).to be(true)
  end

  it 'fetches a contact page from the unversioned endpoint with the maximum supported limit' do
    request = stub_request(:get, 'https://uno.example.com/5566996222471/contacts?cursor=42&limit=200')
              .with(headers: { 'Authorization' => 'secret' })
              .to_return(
                status: 200,
                body: { contacts: [], next_cursor: '42', has_more: false, total_count: 0 }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )

    expect(client.contacts(cursor: '42')).to include('contacts' => [])
    expect(request).to have_been_requested
  end

  it 'imports a contact through the session endpoint' do
    payload = {
      phone_number: '5566999069708',
      user_id: '53515477086263@lid',
      full_name: 'Fran Fernandes',
      first_name: 'Fran',
      username: 'fran'
    }
    request = stub_request(:post, 'https://uno.example.com/5566996222471/contacts/import')
              .with(headers: { 'Authorization' => 'secret' }, body: payload.to_json)
              .to_return(
                status: 200,
                body: { success: true, contact: payload }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )

    expect(client.import_contact(payload)).to include('success' => true)
    expect(request).to have_been_requested
  end

  it 'treats an unavailable session during contact import as transient' do
    stub_request(:post, 'https://uno.example.com/5566996222471/contacts/import')
      .to_return(
        status: 409,
        body: { error: 'session_unavailable' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    expect { client.import_contact(phone_number: '5566999069708', full_name: 'Fran Fernandes') }
      .to raise_error(Whatsapp::Unoapi::ContactSync::Client::TransientError)
  end

  it 'raises the provider mismatch error returned by a non-Zapo session' do
    stub_request(:get, 'https://uno.example.com/5566996222471/contacts?cursor=0&limit=200')
      .to_return(
        status: 409,
        body: { error: 'contact_directory_requires_zapo_provider' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    expect { client.contacts(cursor: '0') }
      .to raise_error(Whatsapp::Unoapi::ContactSync::Client::ProviderMismatchError)
  end
end
