require 'rails_helper'

RSpec.describe Avatar::GroupAvatarService do
  let(:contact) { create(:contact) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, source_id: '123@g.us') }
  let(:service) { described_class.new(contact) }
  let(:group_filename) { "unoapi-profile-#{Digest::SHA256.hexdigest(contact_inbox.source_id)[0, 12]}.png" }

  # insert_all reproduces legacy duplicate has_one links without replacing them.
  def add_avatar(filename)
    blob = ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/avatar.png').open,
                                                  filename: filename, content_type: 'image/png')
    ActiveStorage::Attachment.insert_all!([{ record_type: 'Contact', record_id: contact.id, name: 'avatar', # rubocop:disable Rails/SkipsModelValidations
                                             blob_id: blob.id, created_at: Time.current }])
    ActiveStorage::Attachment.find_by!(record: contact, blob: blob)
  end

  it 'selects the verified group photo instead of an inherited attachment' do
    add_avatar('unoapi-profile-participant.png')
    correct = add_avatar(group_filename)
    add_avatar('unoapi-profile-another-participant.png')
    contact.update!(additional_attributes: { unoapi_profile_picture_id: contact_inbox.source_id })
    expect(service.preferred_attachment.id).to eq(correct.id)
    expect(service.plan[:keep_id]).to eq(correct.id)
  end

  it 'picks the newest verified group image and makes dry-run read only' do
    old = add_avatar(group_filename)
    current = add_avatar(group_filename)
    expect { service.plan }.not_to(change { ActiveStorage::Attachment.order(:id).pluck(:id, :name) })
    expect(service.plan).to eq(status: 'ready', keep_id: current.id, archive_ids: [old.id])
  end

  it 'preserves a newer manual image and excludes manual photos from automatic repair' do
    add_avatar(group_filename)
    manual = add_avatar('manual.png')
    expect(service.preferred_attachment.id).to eq(manual.id)
    expect(service.plan[:status]).to eq('manual_photo_present')
  end

  it 'does not repair unknown images without a verified group photo' do
    add_avatar('unoapi-profile-one.png')
    add_avatar('unoapi-profile-two.png')
    expect(service.plan[:status]).to eq('no_verified_group_photo')
    expect(service.preferred_attachment).to be_nil
  end

  it 'does not repair contacts shared with an individual' do
    add_avatar(group_filename)
    add_avatar('unoapi-profile-one.png')
    create(:contact_inbox, contact: contact, source_id: '456@lid')
    expect(service.plan[:status]).to eq('ambiguous_contact')
  end

  it 'archives duplicates only after writing the backup and is idempotent' do
    old = add_avatar('unoapi-profile-old.png')
    current = add_avatar(group_filename)
    Tempfile.create('group-avatar-backup') do |backup|
      expect { service.repair!(backup: backup) }.not_to change(ActiveStorage::Blob, :count)
      expect(old.reload.name).to eq("group_avatar_history_#{old.id}")
      expect(current.reload.name).to eq('avatar')
      backup.rewind
      snapshot = JSON.parse(backup.read)
      expect(snapshot['attachments'].pluck('id')).to contain_exactly(old.id, current.id)
      expect(service.repair!(backup: backup)[:status]).to eq('no_duplicates')
      expect(old.blob.download).to eq(Rails.root.join('spec/assets/avatar.png').binread)
    end
  end

  it 'does not alter links if persisting the backup fails' do
    old = add_avatar('unoapi-profile-old.png')
    add_avatar(group_filename)
    backup = instance_double(File)
    allow(backup).to receive(:puts).and_raise(IOError)
    expect { service.repair!(backup: backup) }.to raise_error(IOError)
    expect(old.reload.name).to eq('avatar')
  end

  it 'rolls back archived links if attaching the replacement fails' do
    old = add_avatar(group_filename)
    expect { service.replace { raise IOError } }.to raise_error(IOError)
    expect(old.reload.name).to eq('avatar')
  end

  it 'resets stale has_one associations and preserves all prior blobs on replacement' do
    old = add_avatar('manual.png')
    contact.avatar_attachment
    service.replace do
      contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: group_filename, content_type: 'image/png')
    end
    expect(ActiveStorage::Attachment.where(record: contact, name: 'avatar').count).to eq(1)
    expect(old.reload.name).to eq("group_avatar_history_#{old.id}")
    expect(contact.reload.avatar.filename.to_s).to eq(group_filename)
    expect(old.blob.download).to be_present
  end
end
