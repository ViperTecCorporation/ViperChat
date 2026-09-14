require 'rails_helper'

# Resolve archive state when the queued job executes, not when it was enqueued.
RSpec.describe ActionCableBroadcastJob do
  it 'broadcasts the latest archive state only to the supplied private user channel' do
    account = create(:account)
    user = create(:user, account: account)
    conversation = create(:conversation, account: account, assignee: user).reload
    service = Conversations::ArchiveService.new(user, account)
    service.update(conversation, true)
    service.update(conversation, false)
    expect(ActionCable.server).to receive(:broadcast).with(
      user.pubsub_token, { event: 'conversation.archive_changed', data: { account_id: account.id, archived_conversations: [] } }
    )
    described_class.perform_now([user.pubsub_token], 'conversation.archive_changed', { user_id: user.id, account_id: account.id })
  end
end
