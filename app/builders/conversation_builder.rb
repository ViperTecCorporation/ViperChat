class ConversationBuilder
  pattr_initialize [:params!, :contact_inbox!]

  def perform
    look_up_exising_conversation || create_new_conversation
  end

  private

  def look_up_exising_conversation
    return unless @contact_inbox.inbox.lock_to_single_conversation?

    @contact_inbox.conversations.last
  end

  def create_new_conversation
    conversation = ::Conversation.create!(conversation_params)
    auto_assign_kanban_stage(conversation)
    conversation
  end

  def conversation_params
    additional_attributes = params[:additional_attributes]&.permit! || {}
    custom_attributes = params[:custom_attributes]&.permit! || {}
    status = params[:status].present? ? { status: params[:status] } : {}

    # TODO: temporary fallback for the old bot status in conversation, we will remove after couple of releases
    # commenting this out to see if there are any errors, if not we can remove this in subsequent releases
    # status = { status: 'pending' } if status[:status] == 'bot'
    {
      account_id: @contact_inbox.inbox.account_id,
      inbox_id: @contact_inbox.inbox_id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      snoozed_until: params[:snoozed_until],
      assignee_id: params[:assignee_id],
      team_id: params[:team_id]
    }.merge(status)
  end

  def auto_assign_kanban_stage(conversation)
    label = conversation.account.labels.find_by(title: '_kanban_config')
    return unless label&.description&.start_with?('[KANBAN_CONFIG]')

    config = JSON.parse(label.description.delete_prefix('[KANBAN_CONFIG]'))
    pipelines = config['pipelines']
    return unless pipelines.is_a?(Array)

    pipelines.each do |pipeline|
      next unless pipeline.dig('automations', 'auto_create')

      inboxes = pipeline['inboxes'] || []
      next if inboxes.any? && !inboxes.include?(conversation.inbox_id)

      stages = pipeline['stages'] || []
      next if stages.empty?

      conversation.update!(kanban_stage: stages.first['id'])
      break
    end
  rescue JSON::ParserError
    nil
  end
end
