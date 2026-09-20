require 'rails_helper'

RSpec.describe Conversation, '#group_avatar_url' do
  let(:contact) { build_stubbed(:contact, email: 'participant@example.com') }
  let(:contact_inbox) { build_stubbed(:contact_inbox, contact: contact, source_id: '5511999999999') }
  let(:conversation) do
    build_stubbed(:conversation, group: true, group_source_id: '123@g.us', contact: contact, contact_inbox: contact_inbox)
  end

  before do
    allow(contact).to receive(:avatar_url).and_return('https://example.com/avatar.png')
  end

  it 'does not use a participant avatar for a group without a picture' do
    expect(conversation.group_avatar_url).to be_nil
  end

  it 'uses the explicit group picture' do
    conversation.additional_attributes = { 'group_picture' => 'https://example.com/group.png' }
    expect(conversation.group_avatar_url).to eq('https://example.com/group.png')
  end

  it 'preserves an uploaded avatar belonging to the group contact' do
    contact_inbox.source_id = '123@g.us'
    expect(conversation.group_avatar_url).to eq('https://example.com/avatar.png')
  end

  it 'ignores empty picture values instead of using a participant avatar' do
    conversation.additional_attributes = { 'group_picture' => '' }
    expect(conversation.group_avatar_url).to be_nil
  end

  it 'prefers the stored group photo over an expired remote link' do
    contact_inbox.source_id = '123@g.us'
    conversation.additional_attributes = { 'group_picture' => 'https://example.com/expired.jpg' }
    expect(conversation.group_avatar_url).to eq('https://example.com/avatar.png')
  end

  it 'does not promote a generated participant photo to the group fallback' do
    contact_inbox.source_id = '123@g.us'
    contact.additional_attributes = { 'unoapi_profile_picture_id' => '456@lid' }
    filename = "unoapi-profile-#{Digest::SHA256.hexdigest('456@lid')[0, 12]}.jpg"
    blob = instance_double(ActiveStorage::Blob, filename: ActiveStorage::Filename.new(filename))
    allow(contact).to receive(:avatar_attachment).and_return(instance_double(ActiveStorage::Attachment, blob: blob))
    expect(conversation.group_avatar_url).to be_nil
  end

  it 'preserves manual group uploads even with stale participant metadata' do
    contact_inbox.source_id = '123@g.us'
    contact.additional_attributes = { 'unoapi_profile_picture_id' => '456@lid' }
    blob = instance_double(ActiveStorage::Blob, filename: ActiveStorage::Filename.new('manual-group.jpg'))
    allow(contact).to receive(:avatar_attachment).and_return(instance_double(ActiveStorage::Attachment, blob: blob))
    expect(conversation.group_avatar_url).to eq('https://example.com/avatar.png')
  end
end
