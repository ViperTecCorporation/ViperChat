class Api::V1::Accounts::Contacts::ConversationsController < Api::V1::Accounts::Contacts::BaseController
  def index
    # Start with all conversations for this contact
    conversations = Current.account.conversations.includes(
      :assignee, :contact, :inbox
    ).where(contact_id: @contact.id)

    # Apply permission-based filtering using the existing service
    visible = Search::ConversationVisibilityService.new(current_user: Current.user, current_account: Current.account).conversations
    conversations = conversations.where(id: visible.select(:id))

    @conversations = conversations.order(last_activity_at: :desc).limit(20)
  end
end
