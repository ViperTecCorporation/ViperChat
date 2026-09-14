require 'rails_helper'
describe ParticipationListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  describe '#assignee_changed' do
    let(:event_name) { :assignee_changed }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation) }

    it 'adds the assignee as a participant to the conversation' do
      expect(conversation.conversation_participants.map(&:user_id)).not_to include(admin.id)
      listener.assignee_changed(event)
      expect(conversation.conversation_participants.map(&:user_id)).to include(agent.id)
    end

    it 'does not fail if the conversation participant already exists' do
      conversation.conversation_participants.create!(user: agent)
      expect { listener.assignee_changed(event) }.not_to raise_error
    end

    it 'keeps only the current agent by default on existing accounts' do
      conversation.conversation_participants.create!(user: admin)
      listener.assignee_changed(event)
      expect(conversation.conversation_participants.reload.pluck(:user_id)).to eq([agent.id])
      expect(account.reload.last_assignee_as_participant?).to be(true)
    end

    it 'preserves other participants when the account disables the option' do
      account.update!(last_assignee_as_participant: false)
      conversation.conversation_participants.create!(user: admin)
      listener.assignee_changed(event)
      expect(conversation.conversation_participants.reload.pluck(:user_id)).to contain_exactly(admin.id, agent.id)
    end

    it 'uses the latest persisted assignee for a delayed assignment event' do
      conversation.reload
      Conversation.find(conversation.id).update!(assignee: admin)
      expect(conversation.assignee_id).to eq(agent.id)
      listener.assignee_changed(event)
      expect(conversation.conversation_participants.reload.pluck(:user_id)).to eq([admin.id])
    end

    it 'does not remove participants when the agent is unassigned' do
      conversation.conversation_participants.create!(user: admin)
      Conversation.find(conversation.id).update!(assignee: nil)
      listener.assignee_changed(event)
      expect(conversation.conversation_participants.reload.pluck(:user_id)).to eq([admin.id])
    end

    it 'logs a debug message if participant save fails due to a race condition' do
      allow(Rails.logger).to receive(:warn)
      allow(conversation).to receive(:conversation_participants).and_return(double)
      allow(conversation.conversation_participants).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)
      expect { listener.assignee_changed(event) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with('Failed to create conversation participant for account ' \
                                                        "#{account.id} : user #{agent.id} : conversation #{conversation.id}")
    end
  end
end
