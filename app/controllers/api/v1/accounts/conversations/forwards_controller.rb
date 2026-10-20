class Api::V1::Accounts::Conversations::ForwardsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_current_user

  def create
    source_messages = selected_source_messages
    destination_conversation = target_conversation
    contact_inbox = destination_conversation ? nil : target_contact_inbox
    Rails.logger.info(
      '[ForwardMessages] Starting forward ' \
      "account_id=#{current_account.id} user_id=#{Current.user.id} " \
      "target_conversation_id=#{destination_conversation&.id} " \
      "target_contact_id=#{contact_inbox&.contact_id} target_inbox_id=#{contact_inbox&.inbox_id} " \
      "message_ids=#{source_messages.pluck(:id)}"
    )

    service = Messages::ForwardService.new(
      account: current_account,
      user: Current.user,
      source_messages: source_messages,
      target_contact_inbox: contact_inbox,
      target_conversation: destination_conversation,
      requested_provider: permitted_params[:whatsapp_transport]
    )

    @conversation = service.perform

    Rails.logger.info(
      '[ForwardMessages] Completed forward ' \
      "account_id=#{current_account.id} user_id=#{Current.user.id} " \
      "conversation_id=#{@conversation.id} target_contact_id=#{@conversation.contact_id} " \
      "target_inbox_id=#{@conversation.inbox_id} forwarded_message_count=#{source_messages.size}"
    )
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    Rails.logger.error(
      '[ForwardMessages] Failed forward ' \
      "account_id=#{current_account.id} user_id=#{Current.user&.id} " \
      "error=#{e.class}: #{e.message} params=#{permitted_params.to_h}"
    )
    render_could_not_create_error(e.message)
  end

  private

  def permitted_params
    params.permit(:target_contact_id, :target_inbox_id, :target_conversation_id, :whatsapp_transport, message_ids: [])
  end

  def selected_source_messages
    ids = Array(permitted_params[:message_ids]).map(&:to_s).uniq
    raise ArgumentError, 'Select at least one message' if ids.empty?

    messages = current_account.messages.where(conversation_id: @conversation.id, id: ids).index_by { |message| message.id.to_s }
    raise ActiveRecord::RecordNotFound, 'One or more source messages are unavailable' unless messages.size == ids.size

    ids.map { |id| messages.fetch(id) }
  end

  def target_conversation
    return if permitted_params[:target_conversation_id].blank?

    conversation = current_account.conversations.find_by!(display_id: permitted_params[:target_conversation_id])
    authorize conversation, :show?
    authorize conversation.contact, :show?
    raise ArgumentError, 'Target conversation must be different from source conversation' if conversation == @conversation

    conversation
  end

  def target_contact
    @target_contact ||= current_account.contacts.find(permitted_params[:target_contact_id]).tap { |contact| authorize contact, :show? }
  end

  def target_inbox
    @target_inbox ||= begin
      inbox = current_account.inboxes.find(permitted_params[:target_inbox_id])
      canonical = Whatsapp::OperationalInboxService.canonical(inbox: inbox, contact: target_contact)
      Whatsapp::OperationalInboxService.authorize!(inbox: canonical, user: Current.user)
      canonical
    end
  end

  def target_contact_inbox
    if WhatsappInboxLink.for_inbox(target_inbox) && !Whatsapp::OperationalInboxService.group?(target_contact, nil)
      return Whatsapp::OperationalInboxService.contact_inbox(contact: target_contact, inbox: target_inbox)
    end

    ContactInbox.find_by(contact: target_contact, inbox: target_inbox) ||
      ContactInboxBuilder.new(contact: target_contact, inbox: target_inbox, source_id: target_source_id, hmac_verified: false).perform
  end

  def target_source_id
    entry = Contacts::ContactableInboxesService.new(contact: target_contact).get.find { |candidate| candidate[:inbox].id == target_inbox.id }
    entry&.dig(:source_id)
  end

  def ensure_current_user
    head :unauthorized unless Current.user.is_a?(User)
  end
end

Api::V1::Accounts::Conversations::ForwardsController.prepend_mod_with('Api::V1::Accounts::Conversations::ForwardsController')
