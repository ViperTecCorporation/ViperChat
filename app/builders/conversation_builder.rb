class ConversationBuilder
  pattr_initialize [:params!, :contact_inbox!]

  def perform
    return unified_conversation if unified_principal?

    look_up_exising_conversation || create_new_conversation
  end

  private

  def unified_principal?
    link = WhatsappInboxLink.for_inbox(@contact_inbox.inbox)
    link && link.primary_inbox_id == @contact_inbox.inbox_id &&
      !Whatsapp::OperationalInboxService.group?(@contact_inbox.contact, @contact_inbox.source_id)
  end

  def unified_conversation
    @contact_inbox.with_lock do
      conversations = @contact_inbox.contact.conversations.where(inbox_id: @contact_inbox.inbox_id)
      conversations = conversations.where.not(status: :resolved) unless @contact_inbox.inbox.lock_to_single_conversation?
      conversation = conversations.order(created_at: :desc, id: :desc).first
      next create_new_conversation unless conversation

      # Staffing and existing IDs belong to the principal, not to the transport selected for this message.
      conversation.open! if conversation.resolved?
      conversation
    end
  end

  def look_up_exising_conversation
    return unless @contact_inbox.inbox.lock_to_single_conversation?

    @contact_inbox.conversations.last
  end

  def create_new_conversation
    ::Conversation.create!(conversation_params)
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
end
