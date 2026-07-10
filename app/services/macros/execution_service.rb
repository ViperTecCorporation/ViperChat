class Macros::ExecutionService < ActionService
  def initialize(macro, conversation, user)
    super(conversation)
    @macro = macro
    @account = macro.account
    @user = user
    Current.user = user
  end

  def perform
    @macro.actions.each do |action|
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "macro_event.#{@macro.name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def assign_agent(agent_ids)
    agent_ids = agent_ids.map { |id| id == 'self' ? @user.id : id }
    super(agent_ids)
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @macro.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: 'macro.executed')
    WebhookJob.perform_later(webhook_url.first, payload)
  end

  def trigger_typebot(params)
    typebot_url = params[0]
    typebot_slug = params[1]

    return if typebot_url.blank? || typebot_slug.blank?

    @conversation.custom_attributes['typebot_url'] = typebot_url
    @conversation.custom_attributes['typebot_id'] = typebot_slug
    @conversation.custom_attributes.delete('typebot_session_id')
    @conversation.assignee_id = nil
    @conversation.status = :pending
    @conversation.save!

    last_message = @conversation.messages.last
    return if last_message.blank?

    struct = Struct.new(:account, :account_id, :id, :app_id, :settings)
    virtual_hook = struct.new(@conversation.account, @conversation.account_id, nil, 'typebot', {
      'typebot_url' => typebot_url,
      'typebot_id' => typebot_slug
    })

    processor = Integrations::Typebot::ProcessorService.new(
      event_name: 'message.created',
      hook: virtual_hook,
      event_data: { message: last_message }
    )

    start_response = processor.send(:start_chat)
    if start_response && start_response['sessionId']
      @conversation.custom_attributes['typebot_session_id'] = start_response['sessionId']
      @conversation.save!

      processor.send(:process_response, last_message, {
        messages: start_response['messages'] || [],
        client_side_actions: start_response['clientSideActions'] || [],
        input: start_response['input']
      })
    end
  end
end
