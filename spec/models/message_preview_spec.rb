require 'rails_helper'

RSpec.describe Message do
  describe '.without_empty_replies' do
    let(:conversation) { create(:conversation) }
    let!(:media) { create(:message, :with_attachment, conversation: conversation, account: conversation.account, content: nil) }
    let!(:empty_reply) do
      create(:message, conversation: conversation, account: conversation.account, content: nil,
                       content_attributes: { in_reply_to: media.id })
    end

    it 'selects the media instead of a newer empty reply for the list preview' do
      expect(conversation.messages.non_activity_messages.without_empty_replies.first).to eq(media)
      expect(conversation.messages.exists?(empty_reply.id)).to be(true)
    end

    it 'preserves replies with media, text, deleted or unsupported markers' do
      media.update!(content_attributes: { in_reply_to: empty_reply.id })
      expect(conversation.messages.without_empty_replies).to include(media)
      empty_reply.update!(content: 'Reply')
      expect(conversation.messages.without_empty_replies).to include(empty_reply)
      empty_reply.update!(content: nil, content_attributes: { in_reply_to: media.id, deleted: true })
      expect(conversation.messages.without_empty_replies).to include(empty_reply)
      empty_reply.update!(content_attributes: { in_reply_to: media.id, is_unsupported: true })
      expect(conversation.messages.without_empty_replies).to include(empty_reply)
    end
  end
end
