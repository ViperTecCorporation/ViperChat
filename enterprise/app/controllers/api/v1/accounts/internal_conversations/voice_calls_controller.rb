class Api::V1::Accounts::InternalConversations::VoiceCallsController < Api::V1::Accounts::BaseController
  before_action :set_conversation
  before_action :set_voice_inbox
  before_action :set_target_agent

  def create
    authorize @conversation, :show?
    authorize @voice_inbox, :show?

    Rails.logger.info(
      "VOICE_INTERNAL_CALL_CONTROLLER create " \
      "account_id=#{Current.account.id} " \
      "conversation_id=#{@conversation.display_id} " \
      "inbox_id=#{@voice_inbox.id} " \
      "user_id=#{Current.user.id} " \
      "target_agent_id=#{@target_agent.id}"
    )
    result = Voice::InternalCallBuilder.perform!(
      account: Current.account,
      conversation: @conversation,
      inbox: @voice_inbox,
      user: Current.user,
      target_agent: @target_agent
    )

    Rails.logger.info(
      "VOICE_INTERNAL_CALL_CONTROLLER created " \
      "account_id=#{Current.account.id} " \
      "conversation_id=#{@conversation.display_id} " \
      "inbox_id=#{@voice_inbox.id} " \
      "call_sid=#{result[:call_sid]}"
    )
    render json: {
      conversation_id: result[:conversation].display_id,
      inbox_id: @voice_inbox.id,
      call_sid: result[:call_sid]
    }
  rescue ArgumentError => e
    Rails.logger.warn(
      "VOICE_INTERNAL_CALL_CONTROLLER error " \
      "account_id=#{Current.account.id} " \
      "conversation_id=#{@conversation&.display_id} " \
      "inbox_id=#{@voice_inbox&.id} " \
      "error=#{e.message}"
    )
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:internal_conversation_id])
  end

  def set_voice_inbox
    scope = Current.user.assigned_inboxes.where(
      account_id: Current.account.id,
      channel_type: 'Channel::Voice'
    )

    @voice_inbox =
      if params[:voice_inbox_id].present?
        scope.find(params[:voice_inbox_id])
      else
        scope.first
      end

    raise ActiveRecord::RecordNotFound, 'Voice inbox required' if @voice_inbox.blank?
  end

  def set_target_agent
    @target_agent = Current.account.users.find(params.require(:target_agent_id))
  end
end
