class Conversations::EventDataPresenter < SimpleDelegator
  def push_data
    {
      additional_attributes: additional_attributes,
      can_reply: can_reply?,
      channel: inbox.try(:channel_type),
      contact_inbox: contact_inbox,
      group: group?,
      group_source_id: group_source_id,
      group_title: group_title,
      group_picture: group_picture_url,
      group_contacts_count: group? ? group_member_count : 0,
      id: display_id,
      inbox_id: inbox_id,
      messages: push_messages,
      labels: label_list,
      meta: push_meta,
      status: status,
      custom_attributes: custom_attributes,
      snoozed_until: snoozed_until,
      unread_count: unread_incoming_messages.count,
      first_reply_created_at: first_reply_created_at,
      priority: priority,
      waiting_since: waiting_since.to_i,
      kanban_stage: kanban_stage,
      funnel_id: funnel_id,
      stage_id: stage_id,
      **push_timestamps
    }
  end

  # Like #push_data but with message text normalized for external integrations (webhooks).
  def webhook_data
    push_data.merge(messages: webhook_push_messages)
  end

  def funnel_id
    return unless kanban_stage

    config_label = account.labels.find_by(title: '_kanban_config')
    return unless config_label&.description&.start_with?('[KANBAN_CONFIG]')

    config = JSON.parse(config_label.description.delete_prefix('[KANBAN_CONFIG]'))
    pipelines = config['pipelines'] || []
    pipeline = pipelines.find { |p| p['stages']&.any? { |s| s['id'] == kanban_stage } }
    pipeline&.dig('id')
  rescue JSON::ParserError
    nil
  end

  def stage_id
    kanban_stage
  end

  private

  def push_messages
    [messages.where(account_id: account_id).chat.last&.push_event_data].compact
  end

  def webhook_push_messages
    [messages.where(account_id: account_id).chat.last&.webhook_push_event_data].compact
  end

  def push_meta
    {
      sender: contact.push_event_data,
      assignee: assigned_entity&.push_event_data,
      assignee_type: assignee_type,
      team: team&.push_event_data,
      hmac_verified: contact_inbox&.hmac_verified
    }
  end

  def group_picture_url
    return unless group?

    additional_attributes&.dig('group_picture').presence || contact&.avatar_url
  end

  def push_timestamps
    {
      agent_last_seen_at: agent_last_seen_at.to_i,
      contact_last_seen_at: contact_last_seen_at.to_i,
      last_activity_at: last_activity_at.to_i,
      timestamp: last_activity_at.to_i,
      created_at: created_at.to_i,
      updated_at: updated_at.to_f
    }
  end
end
Conversations::EventDataPresenter.prepend_mod_with('Conversations::EventDataPresenter')
