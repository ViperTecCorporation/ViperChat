class Api::V1::Accounts::Conversations::GroupController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_group_conversation
  before_action :ensure_session_group_admin, only: [:update]

  def show; end

  def update
    response = provider_service.update_group(
      group_id: @conversation.group_source_id,
      subject: group_params[:subject],
      description: group_params[:description],
      picture_url: group_picture_url,
      announcement: group_params[:announcement],
      locked: group_params[:locked],
      join_approval_mode: group_params[:join_approval_mode]
    )

    if response.success?
      update_local_group_attributes
      render :show
    else
      render json: { error: provider_error(response, 'Provider failed to update group') }, status: provider_failure_status(response)
    end
  end

  def destroy
    response = provider_service.leave_group(@conversation.group_source_id)

    if response.success?
      mark_session_as_removed
      render :show
    else
      render json: { error: provider_error(response, 'Provider failed to leave group') }, status: provider_failure_status(response)
    end
  end

  def sync
    result = Whatsapp::Unoapi::GroupParticipantsSyncService.new(inbox: @conversation.inbox, conversation: @conversation).perform
    return render :show if result == :ok

    render json: { error: result }, status: :unprocessable_entity
  end

  private

  def ensure_group_conversation
    render json: { error: 'Conversation is not a group' }, status: :not_found unless @conversation.group?
  end

  def ensure_session_group_admin
    render json: { error: 'Connected session must be a group admin' }, status: :forbidden unless @conversation.group_session_admin?
  end

  def provider_service
    @provider_service ||= @conversation.inbox.channel.provider_service
  end

  def group_params
    params.permit(:subject, :description, :picture_url, :announcement, :locked, :join_approval_mode)
  end

  def update_local_group_attributes
    attrs = {
      group_title: group_params[:subject].presence,
      group_description: group_params[:description].presence
    }.compact
    attrs[:group_join_approval_mode] = group_params[:join_approval_mode] if group_params.key?(:join_approval_mode)
    additional_attributes = @conversation.additional_attributes.to_h

    if group_picture_url.present?
      additional_attributes['group_picture'] = group_picture_url
      Avatar::AvatarFromUrlJob.perform_later(@conversation.contact, group_picture_url)
    end

    update_local_group_permissions(additional_attributes)
    attrs[:additional_attributes] = additional_attributes
    @conversation.update!(attrs)
  end

  def update_local_group_permissions(additional_attributes)
    return unless group_params.key?(:announcement) || group_params.key?(:locked)

    if group_params.key?(:announcement)
      additional_attributes['group_announcement'] = ActiveModel::Type::Boolean.new.cast(group_params[:announcement])
    end
    return unless group_params.key?(:locked)

    additional_attributes['group_locked'] = ActiveModel::Type::Boolean.new.cast(group_params[:locked])
  end

  def mark_session_as_removed
    additional_attributes = @conversation.additional_attributes.to_h
    unless additional_attributes['group_session_removed_at'].present?
      @conversation.messages.create!(
        account_id: @conversation.account_id,
        inbox_id: @conversation.inbox_id,
        message_type: :activity,
        content: I18n.t('conversations.activity.whatsapp.group_session_removed')
      )
    end
    additional_attributes['group_session_removed_at'] = Time.current.iso8601
    @conversation.update!(group_session_admin: false, additional_attributes: additional_attributes)
  end

  def group_picture_url
    return if group_params[:picture_url].blank?
    return group_params[:picture_url] unless group_params[:picture_url].start_with?('/')

    "#{ENV.fetch('FRONTEND_URL', request.base_url)}#{group_params[:picture_url]}"
  end

  def provider_error(response, fallback)
    payload = response.parsed_response
    payload = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
    payload.try(:[], :error) || fallback
  end

  def provider_failure_status(response)
    status = response.code.to_i
    status.between?(400, 599) ? status : :unprocessable_entity
  end
end
