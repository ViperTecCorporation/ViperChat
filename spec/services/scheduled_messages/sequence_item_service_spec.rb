require 'rails_helper'

RSpec.describe ScheduledMessages::SequenceItemService do
  let(:scheduled_message) { create(:scheduled_message, status: :sending) }
  let(:item) { scheduled_message.items.first }
  let(:message) do
    create(
      :message,
      account: scheduled_message.account,
      inbox: scheduled_message.inbox,
      conversation: scheduled_message.conversation,
      sender: scheduled_message.sender
    )
  end
  let(:builder) { instance_double(Messages::MessageBuilder, perform: message) }

  before do
    scheduled_message.update!(target_conversation: scheduled_message.conversation)
    item.update!(attachment_blob_ids: ['signed-audio'], voice_message: true)
  end

  it 'creates the native message with audio metadata and attachments' do
    expect(Messages::MessageBuilder).to receive(:new).with(
      scheduled_message.sender,
      scheduled_message.conversation,
      hash_including(attachments: ['signed-audio'], is_voice_message: true, action: 'create')
    ).and_return(builder)

    described_class.new(scheduled_message, 0).perform

    expect(item.reload).to be_dispatching
    expect(item.message_id).to eq(message.id)
  end
end
