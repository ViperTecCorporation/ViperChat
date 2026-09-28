require 'rails_helper'

RSpec.describe Avatar::CleanupGroupAvatarHistoryJob do
  let(:contact) { create(:contact) }
  let(:image) { Rails.root.join('spec/assets/avatar.png').binread }
  let!(:old_blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new(image), filename: 'old.png', content_type: 'image/png') }
  let!(:history) { ActiveStorage::Attachment.create!(record: contact, name: 'avatar', blob: old_blob) }

  before do
    create(:contact_inbox, contact: contact, source_id: '123@g.us')
    history.update!(name: "group_avatar_history_#{history.id}")
    contact.avatar.attach(io: StringIO.new(image), filename: 'current.png', content_type: 'image/png')
  end

  it 'purges history only after confirming the current file exists' do
    allow(contact.avatar.blob.service).to receive(:exist?).and_call_original
    allow(contact.avatar.blob.service).to receive(:exist?).with(contact.avatar.blob.key).and_return(true)

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { described_class.perform_now(contact.id) }

    expect(ActiveStorage::Attachment.exists?(history.id)).to be(false)
    expect(ActiveStorage::Blob.exists?(old_blob.id)).to be(false)
    expect(old_blob.service.exist?(old_blob.key)).to be(false)
    expect(contact.reload.avatar).to be_attached
  end

  it 'preserves history when the current file is missing' do
    allow(contact.avatar.blob.service).to receive(:exist?).with(contact.avatar.blob.key).and_return(false)

    described_class.perform_now(contact.id)

    expect(history.reload).to be_present
    expect(old_blob.download).to eq(image)
  end

  it 'does not purge a blob used by another contact' do
    other_contact = create(:contact)
    other_contact.avatar.attach(old_blob)
    allow(contact.avatar.blob.service).to receive(:exist?).with(contact.avatar.blob.key).and_return(true)

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { described_class.perform_now(contact.id) }

    expect(ActiveStorage::Attachment.exists?(history.id)).to be(false)
    expect(other_contact.reload.avatar.blob.download).to eq(image)
  end

  it 'does not remove repair backups or unrelated attachments' do
    history.update!(name: 'unoapi_inherited_avatar_backup')
    allow(contact.avatar.blob.service).to receive(:exist?).with(contact.avatar.blob.key).and_return(true)

    described_class.perform_now(contact.id)

    expect(history.reload).to be_present
  end
end
