class Api::V1::Accounts::MessageFavoritesController < Api::V1::Accounts::BaseController
  before_action :set_message, only: [:create, :destroy]

  def index
    favorites = visible_favorites

    if params[:ids_only].to_s == 'true'
      params.require(:conversation_id)
      render json: { ids: favorites.pluck(:message_id) }
      return
    end

    favorites = favorites.where('message_favorites.id < ?', params[:before].to_i) if params[:before].present?
    @favorites = favorites.order(id: :desc).limit(26).includes(message: [:sender, :attachments, { conversation: [:contact, :inbox] }]).to_a
    @has_more = @favorites.length > 25
    @favorites = @favorites.first(25)
  end

  def create
    favorite = MessageFavorite.find_or_create_by!(account: current_account, user: current_user, message: @message)
    render json: { id: favorite.id, message_id: @message.id }
  end

  def destroy
    MessageFavorite.where(account: current_account, user: current_user, message: @message).destroy_all
    head :no_content
  end

  private

  def visible_favorites
    conversations = Search::ConversationVisibilityService.new(current_user: current_user, current_account: current_account).conversations
    conversations = conversations.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    conversations = conversations.where(display_id: params[:conversation_id]) if params[:conversation_id].present?
    messages = current_account.messages.where(conversation_id: conversations.select(:id))
    MessageFavorite.where(account: current_account, user: current_user, message_id: messages.select(:id))
  end

  def set_message
    message_id = params[:message_id] || params[:id]
    @message = current_account.messages.find(message_id)
    visible = Search::ConversationVisibilityService.new(current_user: current_user, current_account: current_account).conversations
    raise ActiveRecord::RecordNotFound unless visible.exists?(id: @message.conversation_id)

    authorize @message.conversation, :show?
  end
end
