class Api::V1::Accounts::InternalConversationsController < Api::V1::Accounts::BaseController
  before_action :ensure_internal_inbox, only: [:create]

  def index
    @conversations = Current.account.conversations
                           .joins(:inbox, :conversation_participants)
                           .where(inboxes: { channel_type: 'Channel::Internal' },
                                  conversation_participants: { user_id: Current.user.id })
                           .includes(:contact, { contact: { avatar_attachment: [:blob] } }, :inbox, :assignee)
                           .order(updated_at: :desc)
  end

  def create
    ActiveRecord::Base.transaction do
      contact = Current.account.contacts.create!(name: conversation_title)
      contact_inbox = ContactInbox.create!(contact: contact, inbox: @inbox, source_id: SecureRandom.uuid)

      builder_params = ActionController::Parameters.new(
        additional_attributes: conversation_additional_attributes
      )

      @conversation = ConversationBuilder.new(params: builder_params, contact_inbox: contact_inbox).perform

      conversation_participant_ids.each do |user_id|
        @conversation.conversation_participants.find_or_create_by!(user_id: user_id)
        @inbox.inbox_members.find_or_create_by(user_id: user_id)
      end

      if params[:message].present?
        message = Messages::MessageBuilder.new(Current.user, @conversation, message_params).perform
        # Garantir que mensagens internas nasçam como lidas
        if message&.persisted?
          message.update_column(:status, Message.statuses[:read])
        end
      end
    end

    render 'api/v1/accounts/conversations/create'
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  private

  def ensure_internal_inbox
    @inbox = Current.account.inboxes.find(internal_conversation_params[:inbox_id])
    authorize @inbox, :show?

    return if @inbox.internal_chat?

    render json: { error: 'Inbox is not an internal chat inbox' }, status: :unprocessable_entity
  end

  def internal_conversation_params
    params.permit(:inbox_id, :title, participant_ids: [], message: [:content, :private, :content_type, attachments: []])
  end

  def conversation_participant_ids
    @conversation_participant_ids ||= begin
      ids = Array(internal_conversation_params[:participant_ids]).map(&:to_i)
      ids << Current.user.id
      valid_ids = Current.account.users.where(id: ids).pluck(:id).uniq
      raise StandardError, 'No valid participants for internal chat' if valid_ids.blank?

      valid_ids
    end
  end

  def conversation_title
    internal_conversation_params[:title].presence || participants_label
  end

  def participants_label
    names = Current.account.users.where(id: conversation_participant_ids).pluck(:name)
    names.present? ? names.join(', ') : 'Internal chat'
  end

  def conversation_additional_attributes
    {
      internal_chat: true,
      participants: conversation_participant_ids,
      title: conversation_title
    }
  end

  def message_params
    return {} unless internal_conversation_params[:message].present?

    permitted = internal_conversation_params.require(:message).permit(:content, :private, :content_type, attachments: [])
    permitted.merge(status: :read)
  end
end
