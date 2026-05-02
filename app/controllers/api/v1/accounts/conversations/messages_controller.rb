class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update

  def index
    @messages = message_finder.perform
  end

  def edit
    edited_content = permitted_params[:content].to_s
    edit_sent = Whatsapp::EditMessageService.new(message: message, content: edited_content).perform
    return render json: { error: 'Could not edit message' }, status: :unprocessable_entity unless edit_sent

    @message = message.reload
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text, content_attributes: { deleted: true })
      message.attachments.destroy_all
    end
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {}, source_id: nil)
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  def reaction
    emoji = permitted_params[:emoji].to_s.strip
    return render json: { error: 'Emoji is required' }, status: :unprocessable_entity if emoji.blank?

    unless @conversation.inbox.whatsapp?
      return render json: { error: 'Reactions are only supported for WhatsApp inboxes' },
                    status: :unprocessable_entity
    end
    return render json: { error: 'Message source id is missing' }, status: :unprocessable_entity if message.source_id.blank?

    reaction_sent = Whatsapp::SendReactionService.new(message: message, emoji: emoji).perform
    return render json: { error: 'Could not send reaction' }, status: :unprocessable_entity unless reaction_sent

    updated_attributes = (message.content_attributes || {}).merge(reaction: { emoji: emoji })
    message.update!(content_attributes: updated_attributes)
    @message = message
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error, :emoji, :content)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end
