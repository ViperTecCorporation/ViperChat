require 'rails_helper'

RSpec.describe Conversations::PinService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(user, account) }
  let(:conversation) { create(:conversation, account: account) }

  it 'persists personal pins and allows unpinning without changing assignment or priority' do
    attributes = conversation.attributes.slice('assignee_id', 'team_id', 'priority')
    expect(service.update(conversation, true)).to eq([conversation.display_id])
    expect(described_class.new(user.reload, account).ids).to eq([conversation.display_id])
    expect(conversation.reload.attributes.slice('assignee_id', 'team_id', 'priority')).to eq(attributes)
    expect(service.update(conversation, false)).to eq([])
  end

  it 'limits pins to three, handles repeated requests and keeps other settings' do
    user.update!(ui_settings: { 'theme' => 'dark' })
    conversations = create_list(:conversation, 4, account: account)
    conversations.first(3).each { |item| service.update(item, true) }
    expect { service.update(conversations.last, true) }.to raise_error(ArgumentError, 'pin_limit_reached')
    expect(service.update(conversations.first, true).size).to eq(3)
    expect(user.reload.ui_settings['theme']).to eq('dark')
  end

  it 'isolates users and accounts' do
    service.update(conversation, true)
    expect(described_class.new(create(:user, account: account), account).ids).to eq([])
    expect(described_class.new(user, create(:account)).ids).to eq([])
  end

  it 'sorts pins before pagination without widening the filtered relation' do
    other = create(:conversation, account: account)
    service.update(conversation, true)
    scope = account.conversations.order(id: :desc)
    expect(service.order(scope).limit(1).first).to eq(conversation)
    expect(service.order(scope.where(id: other.id)).to_a).to eq([other])
  end

  it 'supports distinct joined queries and every conversation sort mode' do
    create(:message, conversation: conversation)
    service.update(conversation, true)
    ConversationFinder::SORT_OPTIONS.values.uniq.each do |method, direction|
      scope = account.conversations.joins(:messages).distinct.public_send(method, direction)
      expect(service.order(scope).to_a.map(&:id)).to eq([conversation.id])
    end
  end
end
