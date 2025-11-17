class Api::V1::Accounts::Conversations::ForwardsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_current_user

  def create
    source_messages = current_account.messages.where(id: permitted_params[:message_ids])
    contact_inbox = target_contact_inbox
    Rails.logger.info(
      '[ForwardMessages] Starting forward ' \
      "account_id=#{current_account.id} user_id=#{Current.user.id} " \
      "target_contact_id=#{contact_inbox.contact_id} target_inbox_id=#{contact_inbox.inbox_id} " \
      "message_ids=#{source_messages.pluck(:id)}"
    )

    service = Messages::ForwardService.new(
      account: current_account,
      user: Current.user,
      source_messages: source_messages,
      target_contact_inbox: contact_inbox
    )

    @conversation = service.perform

    Rails.logger.info(
      '[ForwardMessages] Completed forward ' \
      "account_id=#{current_account.id} user_id=#{Current.user.id} " \
      "conversation_id=#{@conversation.id} target_contact_id=#{contact_inbox.contact_id} " \
      "target_inbox_id=#{contact_inbox.inbox_id} forwarded_message_count=#{source_messages.size}"
    )
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
    params.permit(:target_contact_id, :target_inbox_id, message_ids: [])
  end

  def target_contact
    @target_contact ||= current_account.contacts.find(permitted_params[:target_contact_id])
  end

  def target_inbox
    @target_inbox ||= current_account.inboxes.find(permitted_params[:target_inbox_id])
  end

  def target_contact_inbox
    ContactInbox.find_by(contact: target_contact, inbox: target_inbox) ||
      ContactInboxBuilder.new(
        contact: target_contact,
        inbox: target_inbox,
        source_id: nil,
        hmac_verified: false
      ).perform
  end

  def ensure_current_user
    head :unauthorized unless Current.user.is_a?(User)
  end
end

Api::V1::Accounts::Conversations::ForwardsController.prepend_mod_with('Api::V1::Accounts::Conversations::ForwardsController')
