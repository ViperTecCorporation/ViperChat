require 'rails_helper'

RSpec.describe Whatsapp::Unoapi::InheritedGroupAvatarRepair do
  let(:channel) { create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false) }
  let(:contact) { create(:contact, account: channel.account) }
  let(:participant) { create(:contact, account: channel.account) }
  let(:picture_id) { '456@lid' }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '123@g.us') }
  let!(:conversation) do
    create(:conversation, inbox: channel.inbox, account: channel.account, contact: contact, contact_inbox: contact_inbox,
                          group: true, group_source_id: '123@g.us', additional_attributes: { group_picture_id: picture_id })
  end
  let(:repair) { described_class.new(conversation) }

  before do
    create(:contact_inbox, inbox: channel.inbox, contact: participant, source_id: picture_id)
    contact.update!(additional_attributes: { unoapi_profile_picture_id: picture_id, unoapi_avatar_signature: 'old-signature' })
    contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open,
                          filename: "unoapi-profile-#{Digest::SHA256.hexdigest(picture_id)[0, 12]}.png", content_type: 'image/png')
    participant.avatar.attach(contact.avatar.blob)
  end

  it 'reports contamination without changing anything in dry run' do
    expect(repair.perform).to be(true)
    expect(contact.reload.avatar).to be_attached
    expect(conversation.reload.additional_attributes['group_picture_id']).to eq(picture_id)
  end

  it 'archives the wrong group avatar without deleting the file or participant photo and is idempotent' do
    blob_id = contact.avatar.blob.id
    expect { repair.perform(apply: true) }.not_to change(ActiveStorage::Blob, :count)
    expect(contact.reload.avatar).not_to be_attached
    expect(participant.reload.avatar.blob.id).to eq(blob_id)
    expect(ActiveStorage::Attachment.find(contact.additional_attributes.dig(described_class::BACKUP_KEY, 'attachment_id')).name)
      .to eq(described_class::BACKUP_KEY)
    expect(contact.additional_attributes.dig(described_class::BACKUP_KEY, 'avatar_metadata', 'unoapi_profile_picture_id')).to eq(picture_id)
    expect(conversation.reload.additional_attributes).not_to have_key('group_picture_id')
    expect(repair.perform(apply: true)).to be(false)
  end

  it 'preserves a manually uploaded group photo even with stale metadata' do
    contact.avatar.blob.update!(filename: 'legitimate-group.png')
    expect(repair.perform(apply: true)).to be(false)
    expect(contact.reload.avatar).to be_attached
  end

  it 'preserves an explicit group photo URL' do
    conversation.update!(additional_attributes: { group_picture_id: picture_id, group_picture: 'https://example.com/group.png' })
    expect(repair.perform(apply: true)).to be(false)
    expect(contact.reload.avatar).to be_attached
  end

  it 'preserves ambiguous records whose image does not match the participant' do
    participant.avatar.detach
    expect(repair.perform(apply: true)).to be(false)
    expect(contact.reload.avatar).to be_attached
  end

  it 'preserves contacts also used for individual conversations' do
    create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '5551999999999')
    expect(repair.perform(apply: true)).to be(false)
  end

  it 'preserves a genuine group id and opaque picture identifiers' do
    ['123@g.us', 'opaque-picture-id'].each do |valid_id|
      contact.update!(additional_attributes: { unoapi_profile_picture_id: valid_id })
      expect(repair.perform(apply: true)).to be(false)
      expect(contact.reload.avatar).to be_attached
    end
  end

  it 'rolls back the archive when updating the contact fails' do
    allow(contact).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
    expect { repair.perform(apply: true) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(contact.reload.avatar).to be_attached
    expect(contact.additional_attributes).not_to have_key(described_class::BACKUP_KEY)
  end
end
