require 'rails_helper'

RSpec.describe Whatsapp::Unoapi::ProfilePictureClient do
  subject(:client) { described_class.new(channel) }

  let(:channel) do
    create(
      :channel_whatsapp,
      phone_number: '+5566996222471',
      provider: 'unoapi',
      provider_config: {
        'url' => 'https://uno.example.com/',
        'api_key' => 'secret',
        'phone_number_id' => '5566996222471'
      },
      sync_templates: false,
      validate_provider_config: false
    )
  end

  it 'downloads the profile picture by id using the UnoAPI authorization' do
    request = stub_request(:get, 'https://uno.example.com/v13.0/5566996222471/profile-pictures/media%2Favatar-1')
              .with(headers: { 'Accept' => 'image/*', 'Authorization' => 'secret' })
              .to_return(status: 200, body: 'image-bytes', headers: { 'Content-Type' => 'image/jpeg; charset=binary' })

    result = client.fetch('media/avatar-1')

    expect(result.body).to eq('image-bytes')
    expect(result.content_type).to eq('image/jpeg')
    expect(request).to have_been_requested.once
  end

  it 'raises a specific error when the picture no longer exists' do
    stub_request(:get, %r{/v13\.0/5566996222471/profile-pictures/}).to_return(status: 404)

    expect { client.fetch('missing-id') }.to raise_error(described_class::NotFoundError)
  end

  it 'rejects a non-image response' do
    stub_request(:get, %r{/v13\.0/5566996222471/profile-pictures/})
      .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

    expect { client.fetch('avatar-id') }.to raise_error(described_class::InvalidResponseError, /Unsupported/)
  end
end
