class Public::Api::V1::Inboxes::ConversationsController < Public::Api::V1::InboxesController
  include Events::Types
  before_action :set_conversation, only: [:toggle_typing, :update_last_seen, :show, :toggle_status]

  def index
    @conversations = @contact_inbox.hmac_verified? ? @contact_inbox.contact.conversations : @contact_inbox.conversations
  end

  def show; end

  def create
    @conversation = create_conversation
  end

  def toggle_status
    # Check if the conversation is already resolved to prevent redundant operations
    return if @conversation.resolved?

    # Assign the conversation's contact as the resolver
    # This step attributes the resolution action to the contact involved in the conversation
    # If this assignment is not made, the system implicitly becomes the resolver by default
    Current.contact = @conversation.contact

    # Update the conversation's status to 'resolved' to reflect its closure
    @conversation.status = :resolved
    @conversation.save!
  end

  def toggle_typing
    case params[:typing_status]
    when 'on'
      trigger_typing_event(CONVERSATION_TYPING_ON)
    when 'off'
      trigger_typing_event(CONVERSATION_TYPING_OFF)
    end
    head :ok
  end

  def update_last_seen
    @conversation.contact_last_seen_at = DateTime.now.utc
    @conversation.save!
    Rails.logger.info(
      "[Public::Api::V1::Inboxes::ConversationsController] update_last_seen " \
      "inbox_id=#{@conversation.inbox_id} conversation_id=#{@conversation.id} " \
      "display_id=#{@conversation.display_id} contact_id=#{@conversation.contact_id} " \
      "contact_inbox_id=#{@contact_inbox&.id} source_id=#{@contact_inbox&.source_id} " \
      "contact_identifier=#{@conversation.contact&.identifier} contact_phone=#{@conversation.contact&.phone_number}"
    )
    ::Conversations::UpdateMessageStatusJob.perform_later(@conversation.id, @conversation.contact_last_seen_at)
    head :ok
  end

  private

  def set_conversation
    scope = @contact_inbox.hmac_verified? ? @contact_inbox.contact.conversations : @contact_inbox.conversations

    @conversation =
      scope.find_by(display_id: params[:id]) ||
      scope.find_by(id: params[:id])

    raise ActiveRecord::RecordNotFound unless @conversation
  end

  def create_conversation
    ConversationBuilder.new(params: conversation_params, contact_inbox: @contact_inbox).perform
  end

  def trigger_typing_event(event)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, conversation: @conversation, user: @conversation.contact)
  end

  def conversation_params
    params.permit(custom_attributes: {})
  end
end
