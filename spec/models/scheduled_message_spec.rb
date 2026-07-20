require 'rails_helper'

RSpec.describe ScheduledMessage do
  subject(:scheduled_message) { create(:scheduled_message) }

  it 'accepts an agendamento with one valid message' do
    expect(scheduled_message).to be_valid
  end

  it 'rejects a date in the past' do
    scheduled_message.scheduled_at = 1.minute.ago

    expect(scheduled_message).not_to be_valid
    expect(scheduled_message.errors[:scheduled_at]).to include('must be in the future')
  end

  it 'rejects more than five messages' do
    5.times do |position|
      scheduled_message.items.build(position: position + 1, content: "Message #{position}", content_type: 'text')
    end

    expect(scheduled_message).not_to be_valid
    expect(scheduled_message.errors[:items]).to include('must contain between 1 and 5 messages')
  end

  it 'rejects an empty sequence item' do
    scheduled_message.items.first.content = ''

    expect(scheduled_message).not_to be_valid
    expect(scheduled_message.items.first.errors[:base]).to include('message must have content or an attachment')
  end
end
