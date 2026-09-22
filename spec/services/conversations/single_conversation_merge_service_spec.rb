require 'rails_helper'

RSpec.describe Conversations::SingleConversationMergeService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: true) }
  let(:contact) { create(:contact, account: account) }
  let(:link) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let!(:old) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: link, created_at: 2.days.ago) }
  let!(:current) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: link, created_at: 1.day.ago) }
  let(:service) { described_class.new(inbox: inbox, contact: contact) }

  it 'keeps the newest conversation state and never schedules destruction of transferred dependents' do
    old.update!(last_activity_at: Time.current, status: :resolved)
    current.update!(priority: :high, status: :pending, additional_attributes: { 'current' => true })
    message = create(:message, account: account, inbox: inbox, conversation: old, content: 'history')
    attrs = current.reload.attributes
    expect(ActiveRecord::DestroyAssociationAsyncJob).not_to receive(:perform_later)
    result = service.perform
    expect(result.id).to eq(current.id)
    expect(current.reload.attributes).to eq(attrs)
    expect(message.reload.conversation_id).to eq(current.id)
    expect(message.content).to eq('history')
    expect(Conversation.exists?(old.id)).to be(false)
    expect(service.perform.id).to eq(current.id)
  end

  it 'does not merge when the inbox option is disabled' do
    inbox.update!(lock_to_single_conversation: false)
    expect { service.perform }.not_to(change(Conversation, :count))
  end

  it 'uses creation time before ID when selecting the current conversation' do
    old.update!(created_at: Time.current)
    expect(service.perform.id).to eq(old.id)
    expect(Conversation.exists?(current.id)).to be(false)
  end

  it 'does not add participants from the previous conversation' do
    agent = create(:user, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    old.conversation_participants.create!(account: account, user: agent)
    current_ids = current.conversation_participants.pluck(:user_id)
    service.perform
    expect(current.reload.conversation_participants.pluck(:user_id)).to eq(current_ids)
  end

  it 'rolls back the merge and returns the current conversation when historical state conflicts' do
    message = create(:message, account: account, inbox: inbox, conversation: old)
    allow(service).to receive(:ensure_current_state_preserved!).and_raise(Conversations::HistoryMerge::Conflict)
    expect(service.perform.id).to eq(current.id)
    expect(Conversation.exists?(old.id)).to be(true)
    expect(message.reload.conversation_id).to eq(old.id)
  end
end
