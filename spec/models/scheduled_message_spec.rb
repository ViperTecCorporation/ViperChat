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

  it 'defaults to empty transport metadata for existing callers' do
    expect(scheduled_message.whatsapp_transport).to eq({})
    expect(scheduled_message.items.first.whatsapp_transport).to eq({})
  end

  it 'rejects a non-object root snapshot' do
    scheduled_message.whatsapp_transport = 'unoapi'

    expect(scheduled_message).not_to be_valid
    expect(scheduled_message.errors[:whatsapp_transport]).to include('must be an object')
  end

  it 'rejects a non-object item snapshot' do
    item = scheduled_message.items.first
    item.whatsapp_transport = ['unoapi']

    expect(item).not_to be_valid
    expect(item.errors[:whatsapp_transport]).to include('must be an object')
  end

  it 'preserves the root intent without mistaking it for an effective item executor' do
    snapshot = { 'requested_provider' => 'unoapi', 'selection_source' => 'legacy_inbox' }
    scheduled_message.update!(whatsapp_transport: snapshot)
    scheduled_message.items.destroy_all

    scheduled_message.ensure_legacy_item!

    expect(scheduled_message.reload.whatsapp_transport).to eq(snapshot)
    expect(scheduled_message.items.reload.first.whatsapp_transport).to eq({})
  end
end
