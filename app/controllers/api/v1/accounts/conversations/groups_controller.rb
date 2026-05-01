class Api::V1::Accounts::Conversations::GroupsController < Api::V1::Accounts::BaseController
  before_action :set_inbox

  def create
    return render json: { error: 'Inbox must be an UnoAPI WhatsApp inbox' }, status: :unprocessable_entity unless unoapi_whatsapp_inbox?

    response = @inbox.channel.provider_service.create_group(
      subject: group_params[:subject],
      description: group_params[:description],
      participants: participant_payloads,
      join_approval_mode: group_params[:join_approval_mode]
    )
    return render json: { error: provider_error(response, 'Provider failed to create group') }, status: :unprocessable_entity unless response.success?

    @conversation = create_local_group_conversation(response.parsed_response.with_indifferent_access)
    render 'api/v1/accounts/conversations/create'
  end

  private

  def set_inbox
    @inbox = Current.account.inboxes.find(group_params[:inbox_id])
  end

  def unoapi_whatsapp_inbox?
    @inbox.channel_type == 'Channel::Whatsapp' && @inbox.channel.provider == 'unoapi'
  end

  def group_params
    params.permit(:inbox_id, :subject, :description, :join_approval_mode, participants: [:wa_id, :user_id, :phone_number, :phoneNumber, :pn, :jid, :id, :lid])
  end

  def participant_payloads
    @participant_payloads ||= Array(group_params[:participants]).filter_map do |participant|
      participant.to_h.compact_blank.presence
    end
  end

  def create_local_group_conversation(provider_group)
    group_id = provider_group[:id].presence || provider_group[:group_id].presence
    subject = provider_group[:subject].presence || group_params[:subject]
    contact_inbox = ContactInboxWithContactBuilder.new(
      source_id: group_id,
      inbox: @inbox,
      contact_attributes: { email: group_id, name: subject }
    ).perform

    conversation = @inbox.conversations.find_or_initialize_by(group: true, group_source_id: group_id)
    conversation.assign_attributes(
      account_id: Current.account.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      group_title: subject,
      group_description: provider_group[:description].presence || group_params[:description],
      group_invite_link: provider_group[:invite_link],
      group_join_approval_mode: provider_group[:join_approval_mode],
      status: :open
    )
    conversation.save!
    conversation
  end

  def provider_error(response, fallback)
    response.parsed_response.try(:[], 'error') || fallback
  end
end
