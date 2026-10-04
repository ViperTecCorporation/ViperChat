require 'rails_helper'

RSpec.describe 'Web attendance event isolation', type: :request do
  include_context 'with Uno web attendance'

  let(:event) { Events::Base.new('conversation.updated', Time.current, conversation: conversation, web_attendance: true) }

  it 'marks waiting_since updates caused by a Web message for asynchronous delivery' do
    conversation.update!(waiting_since: nil)
    allow(EventDispatcherJob).to receive(:perform_later)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, delivery_destination: 'web')
    expect(EventDispatcherJob).to have_received(:perform_later).with(
      'conversation.updated', anything, hash_including(conversation: conversation, web_attendance: true)
    )
    expect(Current.web_attendance_conversation_id).to be_nil
  end

  it 'keeps ordinary administrative updates unmarked after a Web message' do
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, delivery_destination: 'web')
    allow(EventDispatcherJob).to receive(:perform_later)
    conversation.update!(priority: :high)
    expect(EventDispatcherJob).to have_received(:perform_later).with(
      'conversation.updated', anything, hash_not_including(web_attendance: true)
    )
  end

  it 'marks first reply updates caused by an outgoing Web message' do
    allow(EventDispatcherJob).to receive(:perform_later)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: user,
                     delivery_destination: 'web', message_type: :outgoing)
    expected_data = hash_including(
      conversation: conversation, web_attendance: true, changed_attributes: hash_including('first_reply_created_at')
    )
    expect(EventDispatcherJob).to have_received(:perform_later).with('conversation.updated', anything, expected_data)
    expect(Current.web_attendance_conversation_id).to be_nil
  end

  it 'does not mark another conversation inside a Web context' do
    other = create(:conversation, account: account, inbox: inbox)
    allow(EventDispatcherJob).to receive(:perform_later)
    Current.with_web_attendance(conversation) { other.update!(priority: :high) }
    expect(EventDispatcherJob).to have_received(:perform_later).with(
      'conversation.updated', anything, satisfy { |data| data[:conversation] == other && !data[:web_attendance] }
    )
  end

  it 'restores a nested context even when the operation raises' do
    Current.with_web_attendance(conversation) do
      expect do
        Current.with_web_attendance(instance_double(Conversation, id: conversation.id + 1, contact_id: contact.id + 1)) do
          raise ArgumentError, 'failure'
        end
      end.to raise_error(ArgumentError, 'failure')
      expect(Current.web_attendance_conversation_id).to eq(conversation.id)
      expect(Current.web_attendance_contact_id).to eq(contact.id)
    end
    expect(Current.web_attendance_conversation_id).to be_nil
    expect(Current.web_attendance_contact_id).to be_nil
  end

  it 'marks Web contact activity but preserves subsequent administrative contact updates' do
    conversation.reload
    allow(EventDispatcherJob).to receive(:perform_later)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, delivery_destination: 'web')
    expect(EventDispatcherJob).to have_received(:perform_later).with(
      'contact.updated', anything, hash_including(contact: contact, web_attendance: true)
    )
    expect(Current.web_attendance_contact_id).to be_nil
    contact.update!(name: 'Administrative rename')
    expect(EventDispatcherJob).to have_received(:perform_later).with(
      'contact.updated', anything, satisfy { |data| data[:contact] == contact && !data[:web_attendance] }
    )
  end

  it 'does not mark updates to another contact inside a Web context' do
    other = create(:contact, account: account)
    allow(EventDispatcherJob).to receive(:perform_later)
    Current.with_web_attendance(conversation) { other.update!(name: 'Other contact') }
    expect(EventDispatcherJob).to have_received(:perform_later).with(
      'contact.updated', anything, satisfy { |data| data[:contact] == other && !data[:web_attendance] }
    )
  end

  [:contact_created, :contact_updated].each do |event_method|
    it "isolates Web #{event_method} hooks and webhooks while retaining administrative events" do
      hook = create(:integrations_hook, :leadsquared, account: account, inbox: nil)
      hook_listener = HookListener.instance
      webhook_listener = WebhookListener.instance
      name = event_method.to_s.tr('_', '.')
      contact_event = Events::Base.new(name, Time.current, contact: contact, web_attendance: true, changed_attributes: { 'name' => ['Old', 'New'] })
      arguments = ActiveJob::Arguments.deserialize(ActiveJob::Arguments.serialize([name, contact_event.timestamp, contact_event.data]))
      allow(hook_listener).to receive(:supported_hook_event?).and_return(true)
      allow(HookJob).to receive(:perform_later)
      allow(webhook_listener).to receive(:deliver_account_webhooks)
      hook_listener.public_send(event_method, Events::Base.new(*arguments))
      webhook_listener.public_send(event_method, Events::Base.new(*arguments))
      expect(HookJob).not_to have_received(:perform_later)
      expect(webhook_listener).not_to have_received(:deliver_account_webhooks)
      contact_event.data.delete(:web_attendance)
      hook_listener.public_send(event_method, contact_event)
      webhook_listener.public_send(event_method, contact_event)
      expect(HookJob).to have_received(:perform_later).with(hook, name, contact: contact).once
      expect(webhook_listener).to have_received(:deliver_account_webhooks).once
    end
  end

  it 'skips automation for a serialized Web conversation event' do
    listener = AutomationRuleListener.instance
    allow(listener).to receive(:rule_present?)
    arguments = ActiveJob::Arguments.deserialize(ActiveJob::Arguments.serialize([event.name, event.timestamp, event.data]))
    expect(Current.web_attendance_conversation_id).to be_nil
    listener.conversation_updated(Events::Base.new(*arguments))
    expect(listener).not_to have_received(:rule_present?)
  end

  it 'still evaluates administrative conversation automation' do
    listener = AutomationRuleListener.instance
    allow(listener).to receive(:rule_present?).and_return(false)
    listener.conversation_updated(Events::Base.new('conversation.updated', Time.current, conversation: conversation))
    expect(listener).to have_received(:rule_present?).with('conversation_updated', account)
  end

  it 'skips Web conversation webhooks while retaining administrative webhooks' do
    listener = WebhookListener.instance
    allow(listener).to receive(:deliver_webhook_payloads)
    listener.conversation_updated(event)
    expect(listener).not_to have_received(:deliver_webhook_payloads)
    listener.conversation_updated(Events::Base.new('conversation.updated', Time.current, conversation: conversation))
    expect(listener).to have_received(:deliver_webhook_payloads).once
  end

  it 'skips Web bot events while retaining administrative bot events' do
    web_event = event
    listener = AgentBotListener.instance
    allow(listener).to receive(:agent_bots_for).and_return([])
    listener.conversation_opened(web_event)
    expect(listener).not_to have_received(:agent_bots_for)
    listener.conversation_opened(Events::Base.new('conversation.opened', Time.current, conversation: conversation))
    expect(listener).to have_received(:agent_bots_for).with(inbox, conversation)
  end

  it 'skips Web account hooks while retaining administrative hooks' do
    listener = HookListener.instance
    allow(listener).to receive(:supported_hook_event?).and_return(true)
    hook = create(:integrations_hook, :leadsquared, account: account, inbox: nil)
    allow(HookJob).to receive(:perform_later)
    listener.conversation_created(event)
    expect(HookJob).not_to have_received(:perform_later)
    listener.conversation_created(Events::Base.new('conversation.created', Time.current, conversation: conversation))
    expect(HookJob).to have_received(:perform_later).with(hook, 'conversation.created', conversation: conversation)
  end

  it 'continues publishing Web updates to the agent interface' do
    web_event = event
    listener = ActionCableListener.instance
    allow(listener).to receive(:broadcast)
    listener.conversation_updated(web_event)
    expect(listener).to have_received(:broadcast).at_least(:once)
  end

  it 'marks Web message updates outside a Web context without changing channel events' do
    web_message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, delivery_destination: 'web')
    channel_message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact)
    allow(EventDispatcherJob).to receive(:perform_later)
    web_message.update!(status: :read)
    channel_message.update!(status: :read)
    expect(EventDispatcherJob).to have_received(:perform_later).with(
      'message.updated', anything, hash_including(message: web_message, web_attendance: true)
    )
    expect(EventDispatcherJob).to have_received(:perform_later).with(
      'message.updated', anything, satisfy { |data| data[:message] == channel_message && !data[:web_attendance] }
    )
  end

  message_events = [:message_created, :message_updated]
  %w[AgentBotListener WebhookListener].each do |listener_name|
    message_events.each do |event_method|
      it "isolates #{listener_name} #{event_method} but keeps channel events" do
        listener = listener_name.constantize.instance
        message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, delivery_destination: 'web')
        channel_message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact)
        message_event = Events::Base.new(event_method.to_s.tr('_', '.'), Time.current, message: message)
        allow(listener).to receive(:agent_bots_for).and_return([]) if listener_name == 'AgentBotListener'
        allow(listener).to receive(:deliver_webhook_payloads) if listener_name == 'WebhookListener'
        receiver = listener_name == 'AgentBotListener' ? :agent_bots_for : :deliver_webhook_payloads
        listener.public_send(event_method, message_event)
        expect(listener).not_to have_received(receiver)
        listener.public_send(event_method, Events::Base.new(message_event.name, Time.current, message: channel_message, web_attendance: true))
        expect(listener).not_to have_received(receiver)
        listener.public_send(event_method, Events::Base.new(message_event.name, Time.current, message: channel_message))
        expect(listener).to have_received(receiver).once
      end
    end
  end

  it 'isolates Web message automation while retaining channel automation' do
    listener = AutomationRuleListener.instance
    allow(listener).to receive(:rule_present?).and_return(false)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, delivery_destination: 'web')
    listener.message_created(Events::Base.new('message.created', Time.current, message: message))
    expect(listener).not_to have_received(:rule_present?)
    message.update!(delivery_destination: 'channel')
    listener.message_created(Events::Base.new('message.created', Time.current, message: message, web_attendance: true))
    expect(listener).not_to have_received(:rule_present?)
    listener.message_created(Events::Base.new('message.created', Time.current, message: message))
    expect(listener).to have_received(:rule_present?).with('message_created', account)
  end

  [:message_created, :message_updated].each do |event_method|
    it "isolates Web #{event_method} hooks while retaining channel hooks" do
      listener = HookListener.instance
      allow(listener).to receive(:supported_hook_event?).and_return(true)
      hook = create(:integrations_hook, :leadsquared, account: account, inbox: nil)
      message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, delivery_destination: 'web')
      allow(HookJob).to receive(:perform_later)
      name = event_method.to_s.tr('_', '.')
      listener.public_send(event_method, Events::Base.new(name, Time.current, message: message))
      expect(HookJob).not_to have_received(:perform_later)
      message.update!(delivery_destination: 'channel')
      listener.public_send(event_method, Events::Base.new(name, Time.current, message: message, web_attendance: true))
      expect(HookJob).not_to have_received(:perform_later)
      listener.public_send(event_method, Events::Base.new(name, Time.current, message: message))
      expect(HookJob).to have_received(:perform_later).with(hook, name, message: message, previous_changes: nil).once
    end
  end

  it 'does not schedule Uno delivery for Web messages or reading receipts' do
    allow(SendReplyJob).to receive(:perform_later)
    allow(inbox.channel).to receive(:send_message_update)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: user,
                               delivery_destination: 'web', message_type: :outgoing, status: :sent)
    message.update!(status: :read)
    WebhookListener.instance.message_updated(Events::Base.new('message.updated', Time.current, message: message))
    expect(SendReplyJob).not_to have_received(:perform_later)
    expect(inbox.channel).not_to have_received(:send_message_update)
  end

  it 'does not send a CSAT survey for Web status events but retains administrative surveys' do
    listener = CsatSurveyListener.instance
    conversation.update!(status: :resolved)
    service = instance_double(CsatSurveyService, perform: nil)
    allow(CsatSurveyService).to receive(:new).and_return(service)
    listener.conversation_status_changed(event)
    expect(service).not_to have_received(:perform)
    listener.conversation_status_changed(Events::Base.new('conversation.status_changed', Time.current, conversation: conversation))
    expect(service).to have_received(:perform).once
  end

  it 'isolates Web CSAT responses while retaining channel responses' do
    listener = CsatSurveyListener.instance
    message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact,
                               delivery_destination: 'web', content_type: :input_csat)
    builder = instance_double(CsatSurveys::ResponseBuilder, perform: nil)
    allow(CsatSurveys::ResponseBuilder).to receive(:new).and_return(builder)
    listener.message_updated(Events::Base.new('message.updated', Time.current, message: message))
    expect(builder).not_to have_received(:perform)
    message.update!(delivery_destination: 'channel')
    listener.message_updated(Events::Base.new('message.updated', Time.current, message: message, web_attendance: true))
    expect(builder).not_to have_received(:perform)
    listener.message_updated(Events::Base.new('message.updated', Time.current, message: message))
    expect(builder).to have_received(:perform).once
  end

  if ChatwootApp.enterprise?
    it 'isolates Web Captain events while retaining administrative events' do
      web_event = event
      event_inbox = conversation.inbox
      listener = CaptainListener.instance
      allow(event_inbox).to receive(:captain_active?).and_return(false)
      allow(event_inbox).to receive(:captain_assistant)
      listener.conversation_resolved(web_event)
      expect(event_inbox).not_to have_received(:captain_assistant)
      listener.conversation_resolved(Events::Base.new('conversation.resolved', Time.current, conversation: conversation))
      expect(event_inbox).to have_received(:captain_assistant).once
    end
  end

  %w[channel web].each do |destination|
    it "does not mark #{destination} messages newer than the agent reading cutoff" do
      seen_at = Time.current.change(usec: 0)
      older = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact,
                               delivery_destination: destination, created_at: seen_at)
      newer = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact,
                               delivery_destination: destination, created_at: seen_at + 1.second)
      travel_to seen_at do
        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/web_attendance/seen",
             headers: user.create_new_auth_token, params: { destination: destination }
      end
      expect(response).to have_http_status(:ok)
      expect(older.reload).to be_read
      expect(newer.reload).not_to be_read
    end
  end

  it 'does not mark Web replies newer than the guest reading cutoff' do
    invitation.activate!
    post '/web-attendance/api/session', params: { token: invitation_token }, headers: { 'X-Web-Attendance' => '1' }
    seen_at = Time.current.change(usec: 0)
    older = create(:message, account: account, inbox: inbox, conversation: conversation, sender: user,
                             delivery_destination: 'web', message_type: :outgoing, created_at: seen_at, status: :sent)
    newer = create(:message, account: account, inbox: inbox, conversation: conversation, sender: user,
                             delivery_destination: 'web', message_type: :outgoing, created_at: seen_at + 1.second, status: :sent)
    travel_to(seen_at) { post '/web-attendance/api/seen', headers: { 'X-Web-Attendance' => '1' } }
    expect(response).to have_http_status(:no_content)
    expect(older.reload).to be_read
    expect(newer.reload).not_to be_read
  end
end
