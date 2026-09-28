require 'rails_helper'

RSpec.describe Avatar::AvatarFromUrlJob do
  # The regression only occurs when the outer transaction actually commits.
  self.use_transactional_tests = false

  let(:url) { 'https://example.com/group.png' }
  let(:image) { Rails.root.join('spec/assets/avatar.png').binread }
  let(:metadata) { { etag: 'replacement' } }

  let(:contact) { create(:contact) }
  let(:account) { contact.account }
  let(:previous) { contact.avatar_attachment }

  before do
    create(:contact_inbox, contact: contact, source_id: '123@g.us', inbox: create(:inbox, account: account))
    contact.avatar.attach(io: StringIO.new(image), filename: 'previous.png', content_type: 'image/png')
    previous
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
    stub_request(:get, url).to_return(status: 200, body: image, headers: { 'Content-Type' => 'image/png' })
  end

  after do
    blobs = ActiveStorage::Blob.joins(:attachments)
                               .where(active_storage_attachments: { record_type: 'Contact', record_id: contact.id }).distinct.to_a
    account.destroy!
    blobs.each(&:purge)
  end

  it 'uploads the replacement and preserves the archived image after commit' do
    expect { described_class.perform_now(contact, url, metadata) }
      .to have_enqueued_job(Avatar::CleanupGroupAvatarHistoryJob).with(contact.id)

    replacement = contact.reload.avatar.blob
    expect(replacement.id).not_to eq(previous.blob_id)
    expect(replacement.service.exist?(replacement.key)).to be(true)
    expect(replacement.download).to eq(image)
    expect(previous.reload.name).to eq("group_avatar_history_#{previous.id}")
    expect(previous.blob.download).to eq(image)
    expect(contact.additional_attributes['last_avatar_sync_at']).to be_present
  end

  it 'keeps the previous photo and releases the reservation when uploading fails' do
    signature = described_class.generate_url_hash(url, metadata)
    contact.update!(additional_attributes: { 'avatar_url_enqueued_hash' => signature })
    allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(IOError, 'storage unavailable')

    expect { described_class.perform_now(contact, url, metadata) }.to raise_error(IOError, 'storage unavailable')

    expect(contact.reload.avatar_attachment.id).to eq(previous.id)
    expect(previous.reload.name).to eq('avatar')
    expect(previous.blob.download).to eq(image)
    expect(contact.additional_attributes['last_avatar_sync_at']).to be_nil
    expect(contact.additional_attributes['avatar_url_enqueued_hash']).to be_nil
    expect(Avatar::CleanupGroupAvatarHistoryJob).not_to have_been_enqueued
  end

  it 'does not archive the existing photo for a stale reservation' do
    contact.update!(additional_attributes: { 'avatar_url_enqueued_hash' => 'newer-request' })

    described_class.perform_now(contact, url, metadata)

    expect(contact.reload.avatar_attachment.id).to eq(previous.id)
    expect(previous.reload.name).to eq('avatar')
    expect(contact.additional_attributes['avatar_url_enqueued_hash']).to eq('newer-request')
  end
end
