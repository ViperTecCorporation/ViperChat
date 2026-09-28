require 'rails_helper'

describe Messages::MessageBuilder do
  let(:channel) { create(:channel_whatsapp, provider: 'unoapi', validate_provider_config: false, sync_templates: false) }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: channel.account) }
  let(:user) { create(:user, account: channel.account) }
  let(:location) { { latitude: 0, longitude: -55.5, name: 'Local', address: 'Rua A' } }
  let(:params) { { content_type: 'text', content_attributes: { location: location } } }

  it 'stores one location attachment on the same outgoing message' do
    message = described_class.new(user, conversation, params).perform
    attachment = message.reload.attachments.sole
    expect(attachment).to have_attributes(file_type: 'location', coordinates_lat: 0, coordinates_long: -55.5)
    expect(attachment.file).not_to be_attached
    expect(attachment.account_id).to eq(channel.account_id)
  end

  [nil, '', 'NaN', 'Infinity', 91, -91].each do |latitude|
    it "rejects invalid latitude #{latitude.inspect} without creating a message" do
      location[:latitude] = latitude
      conversation
      expect { described_class.new(user, conversation, params).perform }.to raise_error(ArgumentError)
      expect(conversation.messages.count).to eq(0)
    end
  end

  it 'rejects private notes' do
    expect { described_class.new(user, conversation, params.merge(private: true)).perform }.to raise_error(ArgumentError)
  end

  it 'rejects mixed uploads before the multiple-message branch' do
    expect { described_class.new(user, conversation, params.merge(attachments: %w[a b])).perform }.to raise_error(ArgumentError)
  end
end
