require 'rails_helper'

RSpec.describe Conversation, '#historical_import' do
  let(:conversation) { build(:conversation, historical_import: true, status: :resolved, waiting_since: 1.day.ago, display_id: nil) }

  it 'preserves resolved status with an active bot and clears waiting without broadcasting creation' do
    allow(conversation.inbox).to receive(:active_bot?).and_return(true)
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    expect(conversation).not_to receive(:dispatcher_dispatch).with(described_class::CONVERSATION_CREATED)

    conversation.save!

    expect(conversation).to be_resolved
    expect(conversation.waiting_since).to be_nil
    expect(conversation.display_id).to be_present
    expect(conversation.uuid).to be_present
    expect(conversation.display_id).to eq(described_class.find(conversation.id).display_id)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with('conversation.created', anything, anything)
  end

  [false, true].each do |assignment_v2|
    it "does not invoke assignment during historical insertion (v2: #{assignment_v2})" do
      allow(conversation.inbox).to receive_messages(enable_auto_assignment?: true, auto_assignment_v2_enabled?: assignment_v2)
      expect(AutoAssignment::AssignmentJob).not_to receive(:enqueue_for_inbox)
      expect(AutoAssignment::AgentAssignmentService).not_to receive(:new)

      conversation.save!

      expect(conversation.assignee_id).to be_nil
    end
  end

  it 'does not assign from a team or generate assignment activities on insertion' do
    conversation.team = create(:team, account: conversation.account, allow_auto_assign: true)
    expect(AutoAssignment::AgentAssignmentService).not_to receive(:new)
    expect(conversation).not_to receive(:create_team_change_activity)
    expect(conversation).not_to receive(:dispatcher_dispatch)

    conversation.save!
  end

  it 'runs assignment normally when reopened after reload' do
    conversation.save!
    conversation.reload
    allow(conversation.inbox).to receive_messages(enable_auto_assignment?: true, auto_assignment_v2_enabled?: true)
    expect(AutoAssignment::AssignmentJob).to receive(:enqueue_for_inbox).with(conversation.inbox_id)

    conversation.update!(status: :open)

    expect(conversation).to be_open
    expect(described_class.find(conversation.id).historical_import).to be_nil
  end

  it 'retains the normal bot and waiting behavior without the context' do
    conversation.historical_import = nil
    conversation.status = :open
    allow(conversation.inbox).to receive(:active_bot?).and_return(true)
    expect(conversation).to receive(:notify_conversation_creation).and_call_original

    conversation.save!

    expect(conversation).to be_pending
    expect(conversation.waiting_since).to be_present
  end

  context 'when history arrives after the last seen timestamp' do
    let(:conversation) do
      create(:conversation, historical_import: true, status: :resolved, created_at: 5.days.ago,
                            agent_last_seen_at: 4.days.ago, assignee_last_seen_at: 4.days.ago)
    end
    let!(:imported_message) do
      create(:message, account: conversation.account, conversation: conversation, sender: conversation.contact,
                       historical_import: true, created_at: 2.days.ago, content_attributes: { whatsapp_history_import: true })
    end
    let!(:live_message) do
      create(:message, account: conversation.account, conversation: conversation, sender: conversation.contact,
                       created_at: 1.day.ago, content_attributes: {})
    end

    it 'counts only the live message in agent, assignee and Arel unread counts' do
      expect(conversation.unread_messages.ids).to eq([live_message.id])
      expect(conversation.assignee_unread_messages.ids).to eq([live_message.id])
      expect(conversation.unread_for_destination('channel').ids).to eq([live_message.id])
      expect(described_class.where(id: conversation.id).pick(described_class.unread_messages_count_arel)).to eq(1)
      expect(conversation.messages.ids).to contain_exactly(imported_message.id, live_message.id)
    end

    it 'excludes history with separate destination timestamps and retains live channel messages' do
      conversation.update!(channel_agent_last_seen_at: 4.days.ago, web_agent_last_seen_at: 4.days.ago)

      expect(conversation.unread_messages.ids).to eq([live_message.id])
      expect(conversation.unread_for_destination('channel').ids).to eq([live_message.id])
      expect(conversation.unread_for_destination('web')).to be_empty
      expect(described_class.where(id: conversation.id).pick(described_class.unread_messages_count_arel)).to eq(1)
    end

    it 'excludes history even when no last seen timestamp exists' do
      conversation.update!(agent_last_seen_at: nil, assignee_last_seen_at: nil)

      expect(conversation.unread_messages.ids).to eq([live_message.id])
      expect(conversation.assignee_unread_messages.ids).to eq([live_message.id])
      expect(described_class.where(id: conversation.id).pick(described_class.unread_messages_count_arel)).to eq(1)
    end

    # Reproduce stored legacy JSON/SQL NULL without the store coder normalizing the fixture.
    # rubocop:disable Rails/SkipsModelValidations
    it 'handles legacy JSON strings for historical markers' do
      legacy_attributes = Message.connection.quote({ whatsapp_history_import: true }.to_json.to_json)
      Message.where(id: imported_message.id).update_all(content_attributes: Arel.sql("#{legacy_attributes}::json"))

      expect(conversation.unread_messages.ids).to eq([live_message.id])
      expect(conversation.assignee_unread_messages.ids).to eq([live_message.id])
      expect(described_class.where(id: conversation.id).pick(described_class.unread_messages_count_arel)).to eq(1)
    end

    [nil, { whatsapp_history_import: false }, { unrelated: true }.to_json].each do |attributes|
      it "preserves live messages with content attributes #{attributes.inspect}" do
        raw_attributes = attributes.nil? ? 'NULL' : "#{Message.connection.quote(attributes.to_json)}::json"
        Message.where(id: live_message.id).update_all(content_attributes: Arel.sql(raw_attributes))

        expect(conversation.unread_messages.ids).to eq([live_message.id])
        expect(conversation.assignee_unread_messages.ids).to eq([live_message.id])
        expect(described_class.where(id: conversation.id).pick(described_class.unread_messages_count_arel)).to eq(1)
      end
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
