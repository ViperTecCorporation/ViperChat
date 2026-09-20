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
end
