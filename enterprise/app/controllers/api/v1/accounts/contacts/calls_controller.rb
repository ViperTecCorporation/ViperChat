class Api::V1::Accounts::Contacts::CallsController < Api::V1::Accounts::BaseController
  before_action :contact, only: [:create]
  before_action :contact_from_phone, only: [:create_from_phone]
  before_action :voice_inbox

  def create
    create_call
  end

  def create_from_phone
    create_call
  end

  private

  def create_call
    authorize contact, :show?
    authorize voice_inbox, :show?

    Rails.logger.info(
      "VOICE_OUTBOUND_CALL_CREATE account_id=#{Current.account.id} inbox_id=#{voice_inbox.id} contact_id=#{contact.id} user_id=#{Current.user.id}"
    )
    result = Voice::OutboundCallBuilder.perform!(
      account: Current.account,
      inbox: voice_inbox,
      user: Current.user,
      contact: contact
    )

    conversation = result[:conversation]

    Rails.logger.info(
      "VOICE_OUTBOUND_CALL_CREATED " \
      "account_id=#{Current.account.id} " \
      "inbox_id=#{voice_inbox.id} " \
      "conversation_id=#{conversation.display_id} " \
      "call_sid=#{result[:call_sid]}"
    )
    render json: {
      conversation_id: conversation.display_id,
      inbox_id: voice_inbox.id,
      call_sid: result[:call_sid],
      conference_sid: conversation.additional_attributes['conference_sid']
    }
  end

  def contact
    @contact ||= Current.account.contacts.find(params[:id])
  end

  def contact_from_phone
    phone_number = params.require(:phone_number)
    @contact = Current.account.contacts.find_or_create_by!(phone_number: phone_number) do |record|
      record.name = phone_number if record.name.blank?
    end
    if @contact.name.blank? && phone_number.present?
      @contact.update!(name: phone_number)
    end
  end

  def voice_inbox
    @voice_inbox ||= begin
      inbox = Current.user.assigned_inboxes.where(
        account_id: Current.account.id,
        channel_type: 'Channel::TwilioSms'
      ).find(params.require(:inbox_id))
      raise ActiveRecord::RecordNotFound, 'Voice not enabled' unless inbox.channel.voice_enabled?

      inbox
    end
  end
end
