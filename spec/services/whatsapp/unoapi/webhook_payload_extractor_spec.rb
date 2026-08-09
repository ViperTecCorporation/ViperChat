require 'rails_helper'

RSpec.describe Whatsapp::Unoapi::WebhookPayloadExtractor do
  let(:fixture_path) { Rails.root.join('spec/fixtures/whatsapp/unoapi') }

  def fixture(name)
    JSON.parse(File.read(fixture_path.join(name))).with_indifferent_access
  end

  it 'extracts received messages from a complete envelope' do
    result = described_class.new(params: fixture('interactive_button.json')).perform

    expect(result.source).to eq(:messages)
    expect(result.messages.first[:id]).to eq('UNO_BUTTON_MESSAGE_ID')
  end

  it 'extracts sent echoes from message_echoes' do
    result = described_class.new(params: fixture('outgoing_echo_interactive.json')).perform

    expect(result.source).to eq(:message_echoes)
    expect(result.messages.first[:to]).to eq('5566996222471')
  end

  it 'also accepts an already extracted value payload' do
    value = fixture('interactive_list.json').dig(:entry, 0, :changes, 0, :value)
    result = described_class.new(params: value).perform

    expect(result.messages.first[:id]).to eq('UNO_LIST_MESSAGE_ID')
  end
end
