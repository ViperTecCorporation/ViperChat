require 'rails_helper'

describe Messages::MentionService do
  let(:account) { create(:account) }
  let(:sender) { create(:user, account: account) }
  let(:recipient) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:private_note) { true }
  let(:message_sender) { sender }
  let(:message) do
    create(:message, account: account, conversation: conversation, sender: message_sender,
                     private: private_note, message_type: :outgoing,
                     content: "Olá [@Agente](mention://user/#{recipient.id}/Agente)")
  end

  def deliver_mention
    described_class.new(message: message).perform
  end

  def mentions
    recipient.notifications.where(notification_type: 'conversation_mention', secondary_actor: message)
  end

  context 'with inbox access' do
    before { create(:inbox_member, inbox: inbox, user: recipient) }

    it 'creates a real notification and queues push delivery for a private mention' do
      message
      expect { deliver_mention }.to have_enqueued_job(Notification::PushNotificationJob)
      expect(mentions.count).to eq(1)
    end

    it 'respects disabled mention push preferences without hiding the notification' do
      recipient.notification_settings.find_by!(account: account).update!(push_conversation_mention: false)
      message
      expect { deliver_mention }.not_to have_enqueued_job(Notification::PushNotificationJob)
      expect(mentions.count).to eq(1)
    end

    it 'notifies an archived conversation without unarchiving it and delivers push and email' do
      conversation.update!(assignee: recipient)
      Conversations::ArchiveService.new(recipient, account).update(conversation.reload, true)
      recipient.notification_settings.find_by!(account: account).update!(email_conversation_mention: true)
      deliver_mention
      notification = mentions.sole
      push = Notification::PushNotificationService.new(notification: notification)
      email = Notification::EmailNotificationService.new(notification: notification)
      expect(push).to receive(:notification_subscriptions).and_return([])
      expect(email).to receive(:send_notification_email)
      push.perform
      email.perform
      expect(Conversations::ArchiveService.archived?(recipient, conversation)).to be(true)
    end

    context 'with an external public message' do
      let(:private_note) { false }

      it 'does not treat outgoing customer text as an agent mention' do
        deliver_mention
        expect(mentions).to be_empty
      end
    end
  end

  context 'with team access but no inbox membership' do
    before do
      team = create(:team, account: account)
      create(:team_member, team: team, user: recipient)
      conversation.update!(team: team)
    end

    it 'notifies an agent who can access the conversation through its assigned team' do
      deliver_mention
      expect(mentions.count).to eq(1)
    end
  end

  context 'without conversation access' do
    it 'neither notifies nor grants participation to the mentioned agent' do
      deliver_mention
      expect(mentions).to be_empty
      expect(conversation.conversation_participants.where(user: recipient)).to be_empty
    end
  end

  context 'with internal chat' do
    let(:inbox) { create(:inbox, account: account, channel: create(:channel_internal, account: account)) }
    let(:private_note) { false }

    before do
      membership = create(:inbox_member, inbox: inbox, user: recipient)
      conversation.conversation_participants.create!(user: recipient)
      membership.destroy!
    end

    it 'notifies an existing participant about a non-private agent mention' do
      deliver_mention
      expect(mentions.count).to eq(1)
    end

    it 'does not create a second generic notification for the same message' do
      deliver_mention
      Messages::NewMessageNotificationService.new(message: message).perform
      expect(recipient.notifications.where(secondary_actor: message).count).to eq(1)
    end

    context 'when the sender is a contact' do
      let(:message_sender) { conversation.contact }

      it 'does not interpret untrusted contact text as an agent mention' do
        deliver_mention
        expect(mentions).to be_empty
      end
    end

    context 'when the sender belongs to another account' do
      let(:message_sender) { create(:user) }

      it 'does not process the mention' do
        deliver_mention
        expect(mentions).to be_empty
      end
    end
  end
end
