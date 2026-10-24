class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update
  before_action :reject_web_reaction, only: :reaction

  def index
    @messages = message_finder.perform
    WebAttendance::DeliveryReceiptService.new(conversation: @conversation, messages: @messages, message_type: 'incoming').perform
  end

  def edit
    return render json: { error: 'Use a new Web reply' }, status: :unprocessable_entity if message.web_attendance?

    edited_content = permitted_params[:content].to_s
    edit_sent = Whatsapp::EditMessageService.new(message: message, content: edited_content).perform
    return render json: { error: 'Could not edit message' }, status: :unprocessable_entity unless edit_sent

    @message = message.reload
  end

  def create
    user = Current.user || @resource
    if params[:client_message_id].present?
      @message = Messages::IdempotentCreateService.new(user: user, conversation: @conversation, params: params).perform
      return
    end
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    if params[:delivery_destination] == 'web'
      @conversation.with_lock { @message = mb.perform }
    else
      @message = mb.perform
    end
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    authorize @conversation, :delete_message?

    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text,
                      content_attributes: { deleted: true }.merge(outbox_identity_attributes))
      message.attachments.destroy_all
    end
  end

  def retry
    return if message.blank?

    if message.content_attributes['web_absence_request_key'].present?
      return render json: { error: 'Automatic Web reminders cannot be retried; send a manual invitation instead' },
                    status: :unprocessable_entity
    end

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: retry_content_attributes.merge(outbox_identity_attributes), source_id: nil)
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
  rescue Google::Cloud::Error => e
    # `details` carries the clean human message; `message` includes gRPC debug noise
    render_could_not_create_error(e.details.presence || e.message)
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

  def reject_web_reaction
    return unless message.web_attendance?

    render json: { error: 'WhatsApp reactions are unavailable for Web messages' }, status: :unprocessable_entity
  end

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

  def retry_content_attributes
    return message.content_attributes if message.content_attributes['web_attendance_invitation_id'].present?

    return {} unless message.content_attributes&.dig('whatsapp_interactive', 'type') == 'payment_request'

    { 'whatsapp_interactive' => { 'type' => 'payment_request' } }
  end

  def outbox_identity_attributes
    message.content_attributes.to_h.slice('client_message_id', 'client_message_digest')
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end
