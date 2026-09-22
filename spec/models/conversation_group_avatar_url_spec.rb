require 'rails_helper'

RSpec.describe Conversation, '#group_avatar_url' do
  let(:contact) { create(:contact) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, source_id: source_id) }
  let(:source_id) { '5511999999999' }
  let(:conversation) do
    build_stubbed(:conversation, group: true, group_source_id: '123@g.us', contact: contact, contact_inbox: contact_inbox)
  end
  let(:filename) { 'manual-group.png' }

  before do
    contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: filename, content_type: 'image/png')
  end

  it 'does not use a participant avatar for a group without a picture' do
    expect(conversation.group_avatar_url).to be_nil
  end

  it 'uses the explicit group picture' do
    conversation.additional_attributes = { 'group_picture' => 'https://example.com/group.png' }
    expect(conversation.group_avatar_url).to eq('https://example.com/group.png')
  end

  context 'with a group contact' do
    let(:source_id) { '123@g.us' }

    it 'preserves an uploaded avatar belonging to the group contact' do
      expect(conversation.group_avatar_url).to eq(contact.avatar_url)
    end

    it 'prefers the stored group photo over an expired remote link' do
      conversation.additional_attributes = { 'group_picture' => 'https://example.com/expired.jpg' }
      expect(conversation.group_avatar_url).to eq(contact.avatar_url)
    end

    it 'preserves manual group uploads even with stale participant metadata' do
      contact.update!(additional_attributes: { 'unoapi_profile_picture_id' => '456@lid' })
      expect(conversation.group_avatar_url).to eq(contact.avatar_url)
    end

    context 'with an inherited participant image' do
      let(:filename) { "unoapi-profile-#{Digest::SHA256.hexdigest('456@lid')[0, 12]}.png" }

      it 'does not promote it even after metadata was updated to the group ID' do
        contact.update!(additional_attributes: { 'unoapi_profile_picture_id' => source_id })
        expect(conversation.group_avatar_url).to be_nil
      end
    end
  end
end
