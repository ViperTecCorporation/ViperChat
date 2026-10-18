require 'rails_helper'

RSpec.describe Whatsapp::GroupPayloadNormalizer do
  let(:payload) do
    {
      contacts: [{ group_id: '123@g.us', profile: { name: 'Participant', picture_id: '456@lid' } }],
      messages: [{ group_id: '123@g.us', from_user_id: '456@lid', type: 'text' }]
    }.with_indifferent_access
  end

  it 'does not use the participant picture id when the group picture is missing' do
    result = described_class.new(processed_params: payload, inbox: nil).perform
    expect(result[:group_picture_id]).to be_nil
    expect(result[:sender_picture_id]).to eq('456@lid')
  end

  it 'preserves explicit group photos independently of the sender photo' do
    payload[:contacts][0][:group_picture_id] = '123@g.us'
    payload[:contacts][0][:group_picture] = 'https://example.com/group.jpg'
    result = described_class.new(processed_params: payload, inbox: nil).perform
    expect(result).to include(group_picture_id: '123@g.us', group_picture: 'https://example.com/group.jpg', sender_picture_id: '456@lid')
  end

  it 'preserves opaque Meta group IDs and never interprets BSUID or group JID as a phone' do
    payload[:messages][0].merge!(group_id: 'opaque.meta-group-91', from: 'BR.2339818310092335', from_user_id: 'BR.2339818310092335')
    result = described_class.new(processed_params: payload, inbox: nil).perform
    expect(result).to include(group_source_id: 'opaque.meta-group-91', sender_phone: nil, sender_bsuid: 'BR.2339818310092335')
    payload[:messages][0][:from] = '123@g.us'
    expect(described_class.new(processed_params: payload, inbox: nil).perform[:sender_phone]).to be_nil
  end

  it 'recognizes group echoes without using the destination group as the sender' do
    payload[:message_echoes] = payload.delete(:messages)
    payload[:message_echoes][0].merge!(from: '5566996269251', to: '123@g.us')
    result = described_class.new(processed_params: payload, inbox: nil).perform
    expect(result).to include(group_source_id: '123@g.us', sender_phone: '5566996269251')
  end
end
