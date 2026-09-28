require 'rails_helper'

RSpec.describe Conversations::ResolutionJob do
  let(:account) { create(:account, auto_resolve_after: 10_080, auto_resolve_ignore_waiting: true) }
  let(:conversation) { create(:conversation, account: account) }

  it 'restores waiting after reopening despite a resolution template and private note' do
    travel_to 10.days.ago do
      create(:message, conversation: conversation, message_type: :incoming)
      create(:message, conversation: conversation, message_type: :template, content: 'Closed automatically')
      create(:message, conversation: conversation, message_type: :outgoing, private: true)
      conversation.reload.resolved!
    end
    conversation.reload.open!
    expect(conversation.reload.waiting_since).to be_within(2.seconds).of(Time.current)
    expect(conversation.last_activity_at).to be_within(2.seconds).of(Time.current)
    described_class.perform_now(account: account)
    expect(conversation.reload).to be_open
    travel 8.days do
      described_class.perform_now(account: account)
      expect(conversation.reload).to be_open
    end
  end

  it 'restarts the full inactivity period when waiting conversations may be resolved' do
    account.update!(auto_resolve_ignore_waiting: false)
    travel_to 10.days.ago do
      create(:message, conversation: conversation, message_type: :incoming)
      conversation.reload.resolved!
    end
    conversation.reload.open!
    described_class.perform_now(account: account)
    expect(conversation.reload).to be_open
    travel 8.days do
      described_class.perform_now(account: account)
      expect(conversation.reload).to be_resolved
    end
  end

  it 'does not restore waiting if the last public reply was outgoing' do
    travel_to 10.days.ago do
      create(:message, conversation: conversation, message_type: :incoming)
      create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user, account: account))
      conversation.reload.resolved!
    end
    conversation.reload.open!
    expect(conversation.reload.waiting_since).to be_nil
    described_class.perform_now(account: account)
    expect(conversation.reload).to be_open
    travel 8.days do
      described_class.perform_now(account: account)
      expect(conversation.reload).to be_resolved
    end
  end

  it 'does not reset inactivity on unrelated updates' do
    conversation.update!(last_activity_at: 10.days.ago)
    previous = conversation.reload.last_activity_at
    conversation.update!(agent_last_seen_at: Time.current)
    expect(conversation.reload.last_activity_at).to eq(previous)
  end

  it 'revalidates a stale candidate and does not send a closure message after reopening' do
    account.update!(auto_resolve_ignore_waiting: false, auto_resolve_message: 'Closed')
    conversation.update!(last_activity_at: 10.days.ago)
    job = described_class.new
    scope = account.conversations.where(id: conversation.id)
    current_scope = job.send(:conversation_scope, account)
    allow(scope).to receive(:limit).and_return([conversation])
    conversation.resolved!
    conversation.open!
    # After loading candidates, use the actual current eligibility query.
    allow(job).to receive(:conversation_scope).and_return(scope, current_scope)
    expect(MessageTemplates::Template::AutoResolve).not_to receive(:new)
    job.perform(account: account)
    expect(conversation.reload).to be_open
  end
end
