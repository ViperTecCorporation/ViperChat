require 'rails_helper'

RSpec.describe ScheduledMessages::DeliveryService do
  include ActiveJob::TestHelper

  let(:scheduled_message) { create(:scheduled_message) }

  before do
    scheduled_message.conversation.update!(status: :resolved)
  end

  it 'reopens the single conversation, assigns the sender and queues the first item' do
    scheduled_message.inbox.update!(lock_to_single_conversation: true)

    expect { described_class.new(scheduled_message).perform }
      .to have_enqueued_job(ScheduledMessages::SequenceItemJob).with(scheduled_message.id, 0)

    scheduled_message.reload
    expect(scheduled_message).to be_sending
    expect(scheduled_message.target_conversation).to eq(scheduled_message.conversation)
    expect(scheduled_message.target_conversation).to be_open
    expect(scheduled_message.target_conversation.assignee).to eq(scheduled_message.sender)
    expect(scheduled_message.target_conversation.conversation_participants.exists?(user: scheduled_message.sender)).to be(true)
  end

  it 'creates another conversation when the inbox does not lock to a single conversation' do
    scheduled_message.inbox.update!(lock_to_single_conversation: false)

    described_class.new(scheduled_message).perform

    expect(scheduled_message.reload.target_conversation).not_to eq(scheduled_message.conversation)
  end
end
