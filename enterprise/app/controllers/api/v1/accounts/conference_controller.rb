class Api::V1::Accounts::ConferenceController < Api::V1::Accounts::BaseController
  before_action :set_voice_inbox_for_conference

  def token
    Rails.logger.info(
      "VOICE_CONFERENCE_TOKEN account_id=#{Current.account.id} inbox_id=#{@voice_inbox.id} user_id=#{Current.user.id} provider=#{provider}"
    )
    render json: token_service.new(
      inbox: @voice_inbox,
      user: Current.user,
      account: Current.account
    ).generate
  end

  def create
    conversation = fetch_conversation_by_display_id
    ensure_call_sid!(conversation)
    Rails.logger.info(
      "VOICE_CONFERENCE_CREATE " \
      "account_id=#{Current.account.id} " \
      "inbox_id=#{@voice_inbox.id} " \
      "conversation_id=#{conversation.display_id} " \
      "provider=#{provider}"
    )

    case provider
    when 'twilio'
      conference_service = Voice::Provider::Twilio::ConferenceService.new(conversation: conversation)
      conference_sid = conference_service.ensure_conference_sid
      conference_service.mark_agent_joined(user: current_user)

      render json: {
        status: 'success',
        id: conversation.display_id,
        conference_sid: conference_sid,
        using_webrtc: true,
        provider: provider
      }
    when 'custom'
      response = Voice::Provider::Custom::SessionService.new(
        conversation: conversation,
        inbox: @voice_inbox,
        user: current_user
      ).join(call_sid: conversation.identifier)
      Rails.logger.info(
        "VOICE_CONFERENCE_CREATE custom " \
        "account_id=#{Current.account.id} " \
        "inbox_id=#{@voice_inbox.id} " \
        "conversation_id=#{conversation.display_id} " \
        "conference_sid=#{response[:conference_sid]}"
      )
      render json: response.merge(provider: provider)
    else
      render json: { error: "Unsupported voice provider: #{provider}" }, status: :unprocessable_entity
    end
  end

  def incoming
    unless provider == 'custom'
      render json: { error: 'Inbound calls supported only for custom voice provider' }, status: :unprocessable_entity and return
    end

    call_sid = params.require(:call_sid)
    from_number = params.require(:from_number)

    Rails.logger.info(
      "VOICE_CONFERENCE_INCOMING " \
      "account_id=#{Current.account.id} " \
      "inbox_id=#{@voice_inbox.id} " \
      "call_sid=#{call_sid} " \
      "from_number=#{from_number}"
    )

    conversation = Voice::InboundCallBuilder.perform!(
      account: Current.account,
      inbox: @voice_inbox,
      from_number: from_number,
      call_sid: call_sid
    )

    Rails.logger.info(
      "VOICE_CONFERENCE_INCOMING created " \
      "account_id=#{Current.account.id} " \
      "inbox_id=#{@voice_inbox.id} " \
      "conversation_id=#{conversation.display_id} " \
      "call_sid=#{call_sid}"
    )

    render json: {
      status: 'success',
      conversation_id: conversation.display_id,
      inbox_id: @voice_inbox.id,
      call_sid: call_sid
    }
  rescue ArgumentError => e
    Rails.logger.warn(
      "VOICE_CONFERENCE_INCOMING error " \
      "account_id=#{Current.account.id} " \
      "inbox_id=#{@voice_inbox&.id} " \
      "error=#{e.message}"
    )
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def status
    conversation = fetch_conversation_by_display_id
    call_status = params.require(:call_status)
    call_sid = params[:call_sid].presence || conversation.identifier
    timestamp = params[:timestamp].presence&.to_i

    if call_sid.blank?
      render json: { error: 'call_sid required' }, status: :unprocessable_entity and return
    end

    Rails.logger.info(
      "VOICE_CONFERENCE_STATUS " \
      "account_id=#{Current.account.id} " \
      "inbox_id=#{@voice_inbox.id} " \
      "conversation_id=#{conversation.display_id} " \
      "call_sid=#{call_sid} " \
      "call_status=#{call_status} " \
      "reason=#{params[:reason]}"
    )

    Voice::CallStatus::Manager.new(
      conversation: conversation,
      call_sid: call_sid
    ).process_status_update(call_status, timestamp: timestamp)

    render json: { status: 'success', call_status: call_status }
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    conversation = fetch_conversation_by_display_id
    Rails.logger.info(
      "VOICE_CONFERENCE_DESTROY " \
      "account_id=#{Current.account.id} " \
      "inbox_id=#{@voice_inbox.id} " \
      "conversation_id=#{conversation.display_id} " \
      "provider=#{provider}"
    )
    case provider
    when 'twilio'
      Voice::Provider::Twilio::ConferenceService.new(conversation: conversation).end_conference
    when 'custom'
      Voice::Provider::Custom::SessionService.new(
        conversation: conversation,
        inbox: @voice_inbox,
        user: current_user
      ).leave(call_sid: conversation.identifier)
    end

    render json: { status: 'success', id: conversation.display_id }
  end

  def transfer
    conversation = fetch_conversation_by_display_id
    target_agent = Current.account.users.find(params.require(:target_agent_id))

    unless provider == 'custom'
      render json: { error: 'Transfer supported only for custom voice provider' }, status: :unprocessable_entity and return
    end

    Rails.logger.info(
      "VOICE_CONFERENCE_TRANSFER " \
      "account_id=#{Current.account.id} " \
      "inbox_id=#{@voice_inbox.id} " \
      "conversation_id=#{conversation.display_id} " \
      "target_agent_id=#{target_agent.id} " \
      "call_sid=#{params[:call_sid].presence || conversation.identifier}"
    )
    response = Voice::Provider::Custom::TransferService.new(
      inbox: @voice_inbox,
      conversation: conversation,
      target_agent: target_agent,
      call_sid: params[:call_sid].presence || conversation.identifier
    ).perform

    render json: response.merge(status: 'success')
  end

  private

  def ensure_call_sid!(conversation)
    return conversation.identifier if conversation.identifier.present?

    incoming_sid = params.require(:call_sid)

    conversation.update!(identifier: incoming_sid)
    incoming_sid
  end

  def set_voice_inbox_for_conference
    @voice_inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @voice_inbox, :show?
  end

  def provider
    @provider ||= @voice_inbox.channel.respond_to?(:provider) ? @voice_inbox.channel.provider : 'twilio'
  end

  def token_service
    case provider
    when 'custom'
      Voice::Provider::Custom::TokenService
    else
      Voice::Provider::Twilio::TokenService
    end
  end

  def fetch_conversation_by_display_id
    cid = params[:conversation_id]
    raise ActiveRecord::RecordNotFound, 'conversation_id required' if cid.blank?

    conversation = Current.account.conversations.find_by!(display_id: cid)
    if conversation.inbox_id == @voice_inbox.id
      authorize conversation, :show?
      return conversation
    end

    internal_voice_inbox_id = conversation.additional_attributes&.dig('voice_inbox_id')
    unless internal_voice_inbox_id == @voice_inbox.id
      raise ActiveRecord::RecordNotFound, 'Conversation not linked to voice inbox'
    end

    authorize conversation, :show?
    conversation
  end
end
