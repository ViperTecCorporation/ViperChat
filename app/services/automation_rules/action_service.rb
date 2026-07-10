class AutomationRules::ActionService < ActionService
  def initialize(rule, account, conversation)
    super(conversation)
    @rule = rule
    @account = account
    Current.executed_by = rule
  end

  def perform
    @rule.actions.each do |action|
      @conversation.reload
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

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @rule.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])

    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
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

    virtual_hook = Struct.new(:account, :account_id, :id, :app_id, :settings).new(
      @conversation.account, @conversation.account_id, nil, 'typebot', {
        'typebot_url' => typebot_url,
        'typebot_id' => typebot_slug
      }
    )

    processor = Integrations::Typebot::ProcessorService.new(
      event_name: 'message.created',
      hook: virtual_hook,
      event_data: { message: last_message }
    )

    start_response = processor.send(:start_chat)
    return if start_response.blank? || start_response['sessionId'].blank?

    @conversation.custom_attributes['typebot_session_id'] = start_response['sessionId']
    @conversation.save!

    processor.send(:process_response, last_message, {
      messages: start_response['messages'] || [],
      client_side_actions: start_response['clientSideActions'] || [],
      input: start_response['input']
    })
  end
end
