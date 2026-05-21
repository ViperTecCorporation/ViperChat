require 'rails_helper'

RSpec.describe Conversations::PermissionFilterService do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:another_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }

  # This inbox_member is used to establish the agent's access to the inbox
  before { create(:inbox_member, user: agent, inbox: inbox) }

  describe '#perform' do
    context 'when user is an administrator' do
      it 'returns all conversations' do
        result = described_class.new(
          account.conversations,
          admin,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when user is an agent' do
      it 'returns all conversations with no further filtering' do
        inbox_ids = agent.inboxes.where(account_id: account.id).pluck(:id)

        # The base implementation returns all conversations
        # expecting the caller to filter by assigned inboxes
        result = described_class.new(
          account.conversations.where(inbox_id: inbox_ids),
          agent,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end

      it 'returns internal conversations only from internal inboxes where the agent is a member' do
        administrative_channel = create(:channel_internal, account: account)
        administrative_inbox = create(:inbox, account: account, channel: administrative_channel, name: 'Administrativo')
        executive_channel = create(:channel_internal, account: account)
        executive_inbox = create(:inbox, account: account, channel: executive_channel, name: 'Cupula')

        administrative_conversation = create(:conversation, account: account, inbox: administrative_inbox)
        executive_conversation = create(:conversation, account: account, inbox: executive_inbox)
        create(:inbox_member, user: agent, inbox: administrative_inbox)

        result = described_class.new(
          account.conversations,
          agent,
          account
        ).perform

        expect(result).to include(administrative_conversation)
        expect(result).not_to include(executive_conversation)
      end
    end
  end
end
