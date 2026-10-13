require 'rails_helper'

RSpec.describe Message do
  include_context 'with Uno web attendance'

  it 'does not enqueue SendReply or invoke Uno for outgoing Web messages, including accidentally executed jobs' do
    conversation
    expect(SendReplyJob).not_to receive(:perform_later)
    expect(Whatsapp::SendOnWhatsappService).not_to receive(:new)
    expect(HTTParty).not_to receive(:post)
    message = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: user,
                               delivery_destination: 'web', content: 'Web answer')
    SendReplyJob.perform_now(message.id)
    expect(message.reload.source_id).to be_nil
  end

  it 'suppresses bot, automation and integration webhooks on actual Web message events' do
    conversation
    create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot))
    create(:automation_rule, account: account, event_name: 'message_created')
    expect(AgentBots::WebhookJob).not_to receive(:perform_later)
    expect(AutomationRules::ConditionsFilterService).not_to receive(:new)
    expect(AutomationRules::ActionService).not_to receive(:new)
    message = create(:message, account: account, conversation: conversation, sender: contact, delivery_destination: 'web')
    event = Events::Base.new('message.created', Time.current, message: message)
    AgentBotListener.instance.message_created(event)
    AutomationRuleListener.instance.message_created(event)
    expect(WebhookJob).not_to receive(:perform_later)
    WebhookListener.instance.message_created(event)
  end

  it 'does not let Web messages renew the WhatsApp reply window' do
    create(:message, account: account, conversation: conversation, sender: contact, created_at: 2.days.ago)
    create(:message, account: account, conversation: conversation, sender: contact, delivery_destination: 'web')
    window = Conversations::MessageWindowService.new(conversation.reload)
    allow(window).to receive(:messaging_window).and_return(24.hours)
    expect(window.can_reply?).to be(false)
  end

  it 'keeps channel delivery as the default for existing send flows' do
    conversation
    expect(SendReplyJob).to receive(:perform_later).with(instance_of(Integer))
    message = create(:message, account: account, conversation: conversation, sender: user, message_type: :outgoing)
    expect(message.delivery_destination).to eq('channel')
  end

  it 'rejects bot-originated Web replies and messages after resolution' do
    message = conversation.messages.build(
      account: account, inbox: inbox, message_type: :outgoing, sender: create(:agent_bot),
      delivery_destination: 'web', content: 'Bot answer'
    )
    expect(message).not_to be_valid
    conversation.reload
    conversation.resolved!
    late = conversation.messages.build(
      account: account, inbox: inbox, sender: contact, message_type: :incoming,
      delivery_destination: 'web', content: 'Late'
    )
    expect(late).not_to be_valid
    expect(conversation.reload).to be_resolved
  end
end
