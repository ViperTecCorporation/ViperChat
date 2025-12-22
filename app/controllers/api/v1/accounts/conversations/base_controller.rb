class Api::V1::Accounts::Conversations::BaseController < Api::V1::Accounts::BaseController
  before_action :conversation

  private

  def conversation
    conversation_id = params[:conversation_id] || params[:id]
    @conversation ||= Current.account.conversations.find_by!(display_id: conversation_id)
    authorize @conversation, :show?
  end
end
