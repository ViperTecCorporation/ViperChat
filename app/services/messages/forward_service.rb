class Messages::ForwardService
  SAFE_CONTENT_ATTRIBUTES = %w[contacts location view_once].freeze

  pattr_initialize [:account!, :user!, :source_messages!, :target_contact_inbox, :target_conversation, :requested_provider]

  def perform
    ActiveRecord::Base.transaction do
      validate_sources!
      resolve_destination!
      @conversation = build_conversation
      forward_messages
    end

    @conversation
  end

  private

  def authorize!(record)
    raise Pundit::NotAuthorizedError unless record.account_id == account.id

    context = { user: user, account: account, account_user: account.account_users.find_by!(user_id: user.id) }
    Pundit.authorize(context, record, :show?)
  end

  def validate_sources!
    raise ArgumentError, 'Select at least one message' if source_messages.empty?
    raise ArgumentError, 'Messages must belong to one source conversation' unless source_messages.map(&:conversation_id).uniq.one?

    source_messages.each do |message|
      authorize!(message.conversation)
      raise Pundit::NotAuthorizedError unless message.account_id == account.id

      validate_forwardable!(message)
    end
  end

  def validate_forwardable!(message)
    raise ArgumentError, 'Private messages cannot be forwarded externally' if message.private?
    raise ArgumentError, 'Activity messages cannot be forwarded' if message.activity?
    raise ArgumentError, 'Deleted messages cannot be forwarded' if message.content_attributes.to_h['deleted']
  end

  def resolve_destination!
    destination = target_conversation || target_contact_inbox
    raise ArgumentError, 'A forwarding destination is required' unless destination

    authorize!(destination) if target_conversation
    authorize!(destination.contact)
    source_id = target_conversation ? destination.contact_inbox.source_id : destination.source_id
    inbox = Whatsapp::OperationalInboxService.canonical(
      inbox: destination.inbox, contact: destination.contact, source_id: source_id, conversation: target_conversation
    )
    Whatsapp::OperationalInboxService.authorize!(inbox: inbox, user: user)
    @linked_destination = WhatsappInboxLink.for_inbox(inbox).present? &&
                          !Whatsapp::OperationalInboxService.group?(destination.contact, source_id, target_conversation)
    canonicalize_destination(destination, inbox)
  end

  def canonicalize_destination(destination, inbox)
    return if target_conversation && inbox.id == target_conversation.inbox_id

    @target_contact_inbox = if inbox.id == destination.inbox_id
                              target_contact_inbox
                            else
                              Whatsapp::OperationalInboxService.contact_inbox(contact: destination.contact, inbox: inbox)
                            end
    @target_conversation = nil
  end

  def build_conversation
    if target_conversation
      reopen_and_assign_conversation(target_conversation)
      return target_conversation
    end

    if @linked_destination
      conversation = ConversationBuilder.new(contact_inbox: target_contact_inbox,
                                             params: { status: :open, assignee_id: user.id }).perform
      authorize!(conversation)
      return conversation
    end

    ordinary_conversation
  end

  def ordinary_conversation
    conversation = existing_conversation || Conversation.new(
      account: account,
      inbox: target_contact_inbox.inbox,
      contact: target_contact_inbox.contact,
      contact_inbox: target_contact_inbox,
      status: :open,
      assignee: user
    )
    authorize!(conversation)
    reopen_and_assign_conversation(conversation)
    conversation
  end

  def existing_conversation
    if target_contact_inbox.inbox.lock_to_single_conversation
      target_contact_inbox.contact.conversations
                          .where(inbox_id: target_contact_inbox.inbox_id)
                          .order(:created_at).last
    else
      target_contact_inbox.conversations.open.order(:created_at).last
    end
  end

  def reopen_and_assign_conversation(conversation)
    conversation.status = :open if conversation.resolved? || !@linked_destination
    conversation.assignee = user unless @linked_destination
    conversation.save!
  end

  def forward_messages
    messages = source_messages.map do |original_message|
      new_message = build_forwarded_message(original_message)
      duplicate_attachments(original_message, new_message)
      Whatsapp::UnifiedTransportService.prepare!(message: new_message, requested_provider: requested_provider)
      preflight_transport!(new_message)
      new_message
    end
    messages.each(&:save!)
  end

  def preflight_transport!(message)
    return unless message.inbox.whatsapp? && !message.conversation.group?

    transport = Whatsapp::UnifiedTransportService.new(message: message)
    return unless transport.channel.provider == 'whatsapp_cloud'
    return if transport.can_reply?

    raise ArgumentError, 'The Meta reply window is closed; select ViperConnect or send an approved template'
  end

  def build_forwarded_message(original_message)
    Message.new(
      account: account,
      inbox: @conversation.inbox,
      conversation: @conversation,
      message_type: :outgoing,
      content: original_message.outgoing_content,
      content_type: original_message.sticker? ? :sticker : :text,
      sender: user,
      private: false,
      delivery_destination: 'channel',
      content_attributes: forward_content_attributes(original_message)
    )
  end

  def forward_content_attributes(original_message)
    original_message.content_attributes.to_h.slice(*SAFE_CONTENT_ATTRIBUTES).deep_dup.merge(
      forwarded_from_conversation_id: original_message.conversation_id,
      forwarded_from_message_id: original_message.id
    )
  end

  def duplicate_attachments(original_message, new_message)
    original_message.attachments.each do |attachment|
      raise Pundit::NotAuthorizedError unless attachment.account_id == account.id

      new_attachment = new_message.attachments.build(
        account_id: account.id,
        file_type: attachment.file_type,
        extension: attachment.extension,
        external_url: attachment.external_url,
        fallback_title: attachment.fallback_title,
        meta: attachment.meta.deep_dup,
        coordinates_lat: attachment.coordinates_lat,
        coordinates_long: attachment.coordinates_long
      )

      new_attachment.file.attach(attachment.file.blob) if attachment.file.attached?
    end
  end
end

Messages::ForwardService.prepend_mod_with('Messages::ForwardService')
