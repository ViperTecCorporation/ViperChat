require 'rails_helper'

RSpec.describe ScheduledMessages::DeliveryStatusService do
  let(:scheduled_message) { create(:scheduled_message, status: :sending) }
  let(:message) do
    create(
      :message,
      account: scheduled_message.account,
      inbox: scheduled_message.inbox,
      conversation: scheduled_message.conversation,
      sender: scheduled_message.sender,
      message_type: :outgoing,
      status: :progress
    )
  end
  let(:first_item) { scheduled_message.items.first }

  before do
    scheduled_message.update!(target_conversation: scheduled_message.conversation)
    first_item.update!(status: :dispatching, message: message)
  end

  it 'queues the next message with a ten second interval' do
    scheduled_message.items.create!(position: 1, content: 'Second message', content_type: 'text')
    configured_job = instance_double(ActiveJob::ConfiguredJob)
    allow(ScheduledMessages::SequenceItemJob).to receive(:set).with(wait: 10.seconds).and_return(configured_job)
    expect(configured_job).to receive(:perform_later).with(scheduled_message.id, 1)

    described_class.new(message).sent

    expect(first_item.reload).to be_sent
    expect(scheduled_message.reload).to be_sending
  end

  it 'completes the schedule and applies the label after the last message' do
    described_class.new(message).sent

    expect(scheduled_message.reload).to be_sent
    expect(scheduled_message.target_conversation.labels.map(&:name)).to include(scheduled_message.label.title)
  end

  it 'stops the sequence when the provider rejects a message' do
    message.update!(status: :failed, external_error: 'Provider error')

    described_class.new(message).sent

    expect(first_item.reload).to be_failed
    expect(scheduled_message.reload).to be_failed
    expect(scheduled_message.error_message).to eq('Provider error')
  end
end
