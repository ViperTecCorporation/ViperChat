require 'rails_helper'

RSpec.describe Conversations::DeleteWithAttachmentsJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account) }

  it 'removes attachment records, queues blob purge, and deletes the conversation' do
    message = create(:message, :with_attachment, account: account, inbox: inbox, conversation: conversation)
    attachment = message.attachments.first
    blob = attachment.file.blob

    expect do
      described_class.perform_now(conversation, user, '127.0.0.1')
    end.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)

    expect(Attachment.exists?(attachment.id)).to be(false)
    expect(Conversation.exists?(conversation.id)).to be(false)
  end
end
