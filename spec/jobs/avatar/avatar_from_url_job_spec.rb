require 'rails_helper'

RSpec.describe Avatar::AvatarFromUrlJob do
  let(:valid_url) { 'https://example.com/avatar.png' }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
  end

  it 'enqueues the job' do
    contact = create(:contact)
    expect { described_class.perform_later(contact, 'https://example.com/avatar.png') }
      .to have_enqueued_job(described_class).on_queue('purgable')
  end

  it 'generates the same hash for signed urls that point to the same avatar path' do
    first_url = 'https://cdn.example.com/profile/maria.jpg?X-Amz-Date=20260615T120000Z&X-Amz-Signature=old'
    next_url = 'https://cdn.example.com/profile/maria.jpg?X-Amz-Date=20260615T130000Z&X-Amz-Signature=new'

    expect(described_class.generate_url_hash(first_url)).to eq(described_class.generate_url_hash(next_url))
  end

  it 'generates different hashes for the same avatar path when metadata changes' do
    avatar_url = 'https://cdn.example.com/profile/maria.jpg'
    original_metadata = { etag: 'old-etag', content_length: 1234 }
    next_metadata = { etag: 'new-etag', content_length: 4321 }

    expect(described_class.generate_url_hash(avatar_url, original_metadata))
      .not_to eq(described_class.generate_url_hash(avatar_url, next_metadata))
  end

  it 'reads remote avatar metadata with a ranged GET request' do
    stub_request(:get, valid_url)
      .with(headers: { 'Range' => 'bytes=0-0' })
      .to_return(
        status: 206,
        body: 'a',
        headers: {
          'Content-Type' => 'image/jpeg',
          'Content-Length' => '1',
          'Content-Range' => 'bytes 0-0/41053',
          'ETag' => '"avatar-etag"',
          'Last-Modified' => 'Mon, 15 Jun 2026 19:24:29 GMT'
        }
      )

    expect(described_class.remote_avatar_metadata(valid_url)).to eq(
      'content_length' => '41053',
      'content_type' => 'image/jpeg',
      'etag' => '"avatar-etag"',
      'last_modified' => 'Mon, 15 Jun 2026 19:24:29 GMT'
    )
  end

  context 'with rate-limited avatarable (Contact)' do
    let(:avatarable) { create(:contact) }

    it 'attaches and updates sync attributes' do
      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, valid_url)
      avatarable.reload
      expect(avatarable.avatar).to be_attached
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(valid_url))
      expect(avatarable.additional_attributes['avatar_url_enqueued_hash']).to be_nil
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
    end

    it 'does not enqueue again when the same avatar url is already queued' do
      avatarable.update!(additional_attributes: { 'avatar_url_enqueued_hash' => Digest::SHA256.hexdigest(valid_url) })

      expect(described_class.should_enqueue?(avatarable, valid_url)).to be false
      expect(described_class.enqueue_if_needed(avatarable, valid_url)).to be false
    end

    it 'does not enqueue again when the avatar metadata signature is unchanged' do
      metadata = { etag: 'same-etag', content_length: 1234 }
      avatarable.update!(additional_attributes: { 'avatar_url_hash' => described_class.generate_url_hash(valid_url, metadata) })

      expect(described_class.enqueue_if_needed(avatarable, valid_url, metadata)).to be false
    end

    it 'enqueues again when the same avatar url has different metadata' do
      original_metadata = { etag: 'old-etag', content_length: 1234 }
      next_metadata = { etag: 'new-etag', content_length: 4321 }
      avatarable.update!(additional_attributes: { 'avatar_url_hash' => described_class.generate_url_hash(valid_url, original_metadata) })

      expect do
        described_class.enqueue_if_needed(avatarable, valid_url, next_metadata)
      end.to have_enqueued_job(described_class).with(
        avatarable,
        valid_url,
        { 'content_length' => '4321', 'etag' => 'new-etag' }
      )
    end

    it 'attaches webp avatars and updates sync attributes' do
      webp_url = 'https://example.com/avatar.webp'

      stub_request(:get, webp_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/webp' }
        )

      described_class.perform_now(avatarable, webp_url)
      avatarable.reload

      expect(avatarable.avatar).to be_attached
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(webp_url))
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
    end

    it 'attaches avatars with parameterized content type headers' do
      parameterized_url = 'https://example.com/avatar-parameterized.png'

      stub_request(:get, parameterized_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'IMAGE/PNG; charset=binary' }
        )

      described_class.perform_now(avatarable, parameterized_url)
      avatarable.reload

      expect(avatarable.avatar).to be_attached
      expect(avatarable.avatar.blob.content_type).to eq('image/png')
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(parameterized_url))
    end

    it 'attaches avatars from URLs with embedded basic auth credentials' do
      authenticated_url = 'https://user:pass@example.com/avatar-authenticated.png'

      stub_request(:get, 'https://example.com/avatar-authenticated.png')
        .with(headers: { 'Authorization' => 'Basic dXNlcjpwYXNz' })
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, authenticated_url)
      avatarable.reload

      expect(avatarable.avatar).to be_attached
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(authenticated_url))
    end

    it 'returns early when rate limited' do
      ts = 30.seconds.ago.iso8601
      avatarable.update(additional_attributes: { 'last_avatar_sync_at' => ts })

      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, valid_url)
      avatarable.reload
      expect(avatarable.avatar).not_to be_attached
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
      expect(Time.zone.parse(avatarable.additional_attributes['last_avatar_sync_at']))
        .to be > Time.zone.parse(ts)
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(valid_url))
      expect(WebMock).not_to have_requested(:get, valid_url)
    end

    it 'returns early when hash unchanged' do
      avatarable.update(additional_attributes: { 'avatar_url_hash' => Digest::SHA256.hexdigest(valid_url) })

      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, valid_url)
      expect(avatarable.avatar).not_to be_attached
      avatarable.reload
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_nil
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(valid_url))
      expect(WebMock).not_to have_requested(:get, valid_url)
    end

    it 'updates sync attributes even when URL is invalid' do
      invalid_url = 'invalid_url'
      described_class.perform_now(avatarable, invalid_url)
      avatarable.reload
      expect(avatarable.avatar).not_to be_attached
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(invalid_url))
    end

    it 'updates sync attributes when file download is valid but content type is unsupported' do
      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: '<invalid>content</invalid>',
          headers: { 'Content-Type' => 'application/xml' }
        )

      described_class.perform_now(avatarable, valid_url)
      avatarable.reload

      expect(avatarable.avatar).not_to be_attached
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(valid_url))
    end

    it 'updates sync attributes when the avatar URL is blocked by SSRF protection' do
      blocked_url = 'http://127.0.0.1/avatar.png'

      expect do
        described_class.perform_now(avatarable, blocked_url)
      end.not_to raise_error

      avatarable.reload
      expect(avatarable.avatar).not_to be_attached
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(blocked_url))
    end
  end

  context 'with regular avatarable' do
    let(:avatarable) { create(:agent_bot) }

    it 'downloads and attaches avatar' do
      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, valid_url)
      expect(avatarable.avatar).to be_attached
    end
  end

  # ref: https://github.com/chatwoot/chatwoot/issues/10449
  it 'does not raise error when downloaded file has no filename (invalid content)' do
    contact = create(:contact)
    invalid_file = Tempfile.new('avatar-without-name')

    allow(SafeFetch).to receive(:fetch)
      .with(
        valid_url,
        max_bytes: Avatar::AvatarFromUrlJob::MAX_DOWNLOAD_SIZE,
        allowed_content_type_prefixes: [],
        allowed_content_types: Avatar::AvatarFromUrlJob::ALLOWED_CONTENT_TYPES
      ).and_yield(
        SafeFetch::Result.new(
          tempfile: invalid_file,
          filename: nil,
          content_type: 'image/png'
        )
      )

    expect { described_class.perform_now(contact, valid_url) }.not_to raise_error
    expect(contact.reload.avatar).not_to be_attached
  ensure
    invalid_file.close!
  end

  it 'skips sync attribute updates when URL is nil' do
    contact = create(:contact)

    expect { described_class.perform_now(contact, nil) }.not_to raise_error

    contact.reload
    expect(contact.additional_attributes['last_avatar_sync_at']).to be_nil
    expect(contact.additional_attributes['avatar_url_hash']).to be_nil
  end
end
