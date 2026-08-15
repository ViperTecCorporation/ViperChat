require 'rails_helper'

RSpec.describe Avatar::AvatarFromUnoapiJob do
  let(:channel) do
    create(
      :channel_whatsapp,
      provider: 'unoapi',
      provider_config: { 'url' => 'https://uno.example.com', 'api_key' => 'secret', 'phone_number_id' => '5566996222471' },
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:contact) { create(:contact, account: channel.account) }
  let(:picture_id) { 'avatar-123' }

  it 'enqueues only once for the same channel, picture id and metadata' do
    expect do
      2.times { described_class.enqueue_if_needed(contact, channel, picture_id, { etag: 'v1' }) }
    end.to have_enqueued_job(described_class).once
  end

  it 'attaches the authenticated UnoAPI response and records its identity' do
    result = Whatsapp::Unoapi::ProfilePictureClient::Result.new(
      body: Rails.root.join('spec/assets/avatar.png').binread,
      content_type: 'image/png'
    )
    client = instance_double(Whatsapp::Unoapi::ProfilePictureClient, fetch: result)
    allow(Whatsapp::Unoapi::ProfilePictureClient).to receive(:new).with(channel).and_return(client)
    signature = described_class.signature_for(channel, picture_id, {})

    described_class.perform_now(contact, channel, picture_id, { 'signature' => signature })

    contact.reload
    expect(contact.avatar).to be_attached
    expect(contact.avatar.content_type).to eq('image/png')
    expect(contact.additional_attributes).to include(
      'unoapi_avatar_signature' => signature,
      'unoapi_profile_picture_id' => picture_id
    )
  end

  it 'uses the old URL as fallback only when the id route returns 404' do
    fallback_url = 'https://cdn.example.com/avatar.jpg'
    client = instance_double(Whatsapp::Unoapi::ProfilePictureClient)
    allow(client).to receive(:fetch).and_raise(Whatsapp::Unoapi::ProfilePictureClient::NotFoundError)
    allow(Whatsapp::Unoapi::ProfilePictureClient).to receive(:new).with(channel).and_return(client)
    allow(Avatar::AvatarFromUrlJob).to receive(:enqueue_if_needed)

    described_class.perform_now(
      contact,
      channel,
      picture_id,
      { 'avatar_metadata' => { etag: 'v1' }, 'fallback_url' => fallback_url, 'signature' => 'signature' }
    )

    expect(Avatar::AvatarFromUrlJob).to have_received(:enqueue_if_needed)
      .with(contact, fallback_url, { 'etag' => 'v1' })
  end

  it 'never serializes the UnoAPI token in the queued arguments' do
    described_class.enqueue_if_needed(contact, channel, picture_id)

    serialized_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.to_json
    expect(serialized_jobs).not_to include('secret')
  end
end
