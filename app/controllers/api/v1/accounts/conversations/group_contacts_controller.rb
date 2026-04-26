class Api::V1::Accounts::Conversations::GroupContactsController < Api::V1::Accounts::Conversations::BaseController
  RESULTS_PER_PAGE = 25
  before_action :ensure_session_group_admin, only: [:destroy]

  def index
    @group_contacts = @conversation.group_contacts.includes(:contact).page(params[:page]).per(RESULTS_PER_PAGE)
  end

  def destroy
    participants = Array(params[:participants]).map(&:to_s).reject(&:blank?)
    return head :no_content if participants.blank?

    remove_provider_participants(participants)
    @conversation.group_contacts.includes(contact: :contact_inboxes).find_each do |group_contact|
      group_contact.destroy! if participants.include?(participant_identifier(group_contact))
    end

    head :no_content
  end

  private

  def ensure_session_group_admin
    render json: { error: 'Connected session must be a group admin' }, status: :forbidden unless @conversation.group_session_admin?
  end

  def remove_provider_participants(participants)
    return unless @conversation.inbox.channel.provider == 'unoapi'

    @conversation.inbox.channel.provider_service.remove_group_participants(
      group_id: @conversation.group_source_id,
      participants: participants
    )
  end

  def participant_identifier(group_contact)
    metadata = group_contact.metadata || {}
    metadata['wa_id'].presence || metadata['user_id'].presence || metadata['jid'].presence || metadata['lid'].presence ||
      group_contact.contact.contact_inboxes.find { |contact_inbox| contact_inbox.inbox_id == @conversation.inbox_id }&.source_id ||
      group_contact.contact.phone_number || group_contact.contact.bsuid || group_contact.contact.email
  end
  helper_method :participant_identifier
end
