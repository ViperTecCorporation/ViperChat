require 'rails_helper'

RSpec.describe Whatsapp::HistoryWebhookChunks do
  let(:messages) { 4.times.map { |index| { 'id' => "history-#{index}", 'text' => { 'body' => 'a' * 80_000 } } } }
  let(:change) do
    { 'field' => 'history', 'value' => { 'metadata' => { 'phone_number_id' => 'configured-phone' }, 'history' => [
      { 'metadata' => { 'phase' => 0, 'progress' => 80 }, 'threads' => [{ 'id' => '5566996269251', 'messages' => messages }] }
    ] } }
  end

  it 'splits large batches before truncation preserving each public ID, peer and metadata' do
    parts = described_class.split(change)
    expect(parts.size).to eq(4)
    expect(parts.map { |part| part.dig('value', 'history', 0, 'threads', 0, 'messages', 0, 'id') }).to eq(messages.pluck('id'))
    parts.each do |part|
      expect(part.to_json.bytesize).to be < WhatsappManagementEvent::MAX_PAYLOAD_BYTES
      expect(part.dig('value', 'history', 0, 'threads', 0, 'id')).to eq('5566996269251')
      expect(part.dig('value', 'metadata', 'phone_number_id')).to eq('configured-phone')
    end
  end

  it 'leaves small batches and non-history events intact' do
    expect(described_class.split(change.merge('field' => 'account_update'))).to eq([change.merge('field' => 'account_update')])
    messages.each { |message| message['text']['body'] = 'small' }
    expect(described_class.split(change)).to eq([change])
  end

  it 'splits official top-level media follow-ups without losing messages or phone scope' do
    change['value'].delete('history')
    change['value']['messages'] = messages
    parts = described_class.split(change)
    expect(parts.size).to eq(4)
    expect(parts.flat_map { |part| part.dig('value', 'messages') }).to eq(messages)
    expect(parts.map { |part| part.dig('value', 'metadata') }.uniq).to eq([change['value']['metadata']])
  end

  it 'does not erase an oversized lifecycle-only history envelope with no messages to split' do
    change['value']['history'] = [{ 'threads' => [], 'errors' => [{ 'code' => 2593109 }] }]
    change['value']['large'] = 'a' * WhatsappManagementEvent::MAX_PAYLOAD_BYTES
    expect(described_class.split(change)).to eq([change])
  end

  it 'keeps malformed envelopes for the existing bounded diagnostic path' do
    change['value']['history'].first['threads'] = 'malformed'
    change['value']['large'] = 'a' * WhatsappManagementEvent::MAX_PAYLOAD_BYTES
    expect(described_class.split(change)).to eq([change])
  end
end
