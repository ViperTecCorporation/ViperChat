class Api::V1::Accounts::ScheduledMessagesController < Api::V1::Accounts::BaseController
  before_action :fetch_scheduled_message, only: [:update, :destroy]

  def index
    render json: filtered_messages.order(:scheduled_at).map { |message| serialize(message) }
  end

  def create
    # Conversation routes and the conversation store expose display_id, not the
    # database primary key. Keep this endpoint consistent with the other
    # conversation APIs so accounts with non-matching IDs can schedule messages.
    conversation = current_account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    sender = current_account.users.find(permitted_params[:sender_id] || current_user.id)
    ensure_sender_allowed!(sender)
    scheduled_message = build_scheduled_message(conversation, sender)
    scheduled_message.transaction do
      build_items(scheduled_message)
      scheduled_message.save!
      attach_item_files!(scheduled_message)
    end
    render json: serialize(scheduled_message), status: :created
  end

  def update
    authorize_owner_or_admin!
    return render_uneditable unless editable?

    sender = permitted_params[:sender_id].present? ? current_account.users.find(permitted_params[:sender_id]) : @scheduled_message.sender
    ensure_sender_allowed!(sender)
    @scheduled_message.transaction do
      @scheduled_message.update!(schedule_update_attributes(sender))
      replace_items! if permitted_messages.present?
    end
    render json: serialize(@scheduled_message)
  end

  def destroy
    authorize_owner_or_admin!
    @scheduled_message.cancelled!
    head :no_content
  end

  private

  def fetch_scheduled_message
    @scheduled_message = current_account.scheduled_messages.find(params[:id])
  end

  def permitted_params
    params.require(:scheduled_message).permit(:scheduled_at, :label_id, :reason, :content, :content_type, :sender_id,
                                              content_attributes: {}, attachment_blob_ids: [],
                                              messages: [:content, :content_type, :voice_message,
                                                         { content_attributes: {}, attachment_blob_ids: [] }])
  end

  def schedule_attributes
    permitted_params.except(:sender_id, :attachment_blob_ids, :messages).to_h
  end

  def permitted_messages
    raw_messages = permitted_params[:messages]
    return if raw_messages.blank?

    raw_messages.map(&:to_h)
  end

  def build_items(scheduled_message)
    messages = permitted_messages || [legacy_message_attributes]
    messages.each_with_index do |item_attributes, position|
      scheduled_message.items.build(item_attributes.merge(position: position))
    end
  end

  def legacy_message_attributes
    {
      'content' => permitted_params[:content],
      'content_type' => permitted_params[:content_type].presence || 'text',
      'content_attributes' => permitted_params[:content_attributes] || {},
      'attachment_blob_ids' => permitted_params[:attachment_blob_ids] || []
    }
  end

  def attach_item_files!(scheduled_message)
    messages = permitted_messages || [legacy_message_attributes]
    scheduled_message.items.each_with_index do |item, index|
      signed_ids = messages[index]&.fetch('attachment_blob_ids', []) || []
      item.files.attach(signed_ids) if signed_ids.present?
    end
    sync_legacy_fields!(scheduled_message)
  end

  def sync_legacy_fields!(scheduled_message)
    first_item = scheduled_message.items.first
    return unless first_item

    scheduled_message.update!(
      content: first_item.content,
      content_type: first_item.content_type,
      content_attributes: first_item.content_attributes,
      attachment_blob_ids: first_item.attachment_blob_ids
    )
  end

  def filtered_messages
    messages = scheduled_messages_scope.where(scheduled_at: requested_time_range)
    { inbox_id: params[:inbox_id], sender_id: params[:sender_id], label_id: params[:label_id], status: params[:status] }.each do |key, value|
      messages = messages.where(key => value) if value.present?
    end
    messages
  end

  def scheduled_messages_scope
    current_account.scheduled_messages.includes(
      :label, :inbox, :conversation, :target_conversation,
      contact: { avatar_attachment: :blob },
      sender: { avatar_attachment: :blob },
      items: { files_attachments: :blob }
    )
  end

  def build_scheduled_message(conversation, sender)
    current_account.scheduled_messages.new(
      schedule_attributes.merge(
        scheduled_at: account_time_zone.parse(permitted_params[:scheduled_at]),
        conversation: conversation,
        contact: conversation.contact,
        inbox: conversation.inbox,
        created_by: current_user,
        sender: sender
      )
    )
  end

  def editable?
    !@scheduled_message.sending?
  end

  def render_uneditable
    render json: { error: 'Only pending or failed schedules can be edited' }, status: :unprocessable_entity
  end

  def schedule_update_attributes(sender)
    attributes = schedule_attributes.merge(sender: sender)
    attributes[:scheduled_at] = account_time_zone.parse(permitted_params[:scheduled_at]) if permitted_params[:scheduled_at].present?
    if @scheduled_message.failed?
      attributes[:status] = :scheduled
      attributes[:error_message] = nil
    end
    attributes
  end

  def replace_items!
    @scheduled_message.items.destroy_all
    build_items(@scheduled_message)
    @scheduled_message.save!
    attach_item_files!(@scheduled_message)
  end

  def ensure_sender_allowed!(sender)
    return if current_account.account_users.find_by(user: current_user)&.administrator? || sender == current_user

    raise Pundit::NotAuthorizedError
  end

  def authorize_owner_or_admin!
    return if @scheduled_message.created_by == current_user
    return if current_account.account_users.find_by(user: current_user)&.administrator?

    raise Pundit::NotAuthorizedError
  end

  def serialize(message)
    ScheduledMessages::Serializer.new(message, current_user).as_json
  end

  def account_time_zone
    timezone_name = current_account.reporting_timezone.presence
    timezone_name ? (ActiveSupport::TimeZone[timezone_name] || Time.zone) : Time.zone
  end

  def requested_time_range
    return Time.iso8601(params[:start_at])...Time.iso8601(params[:end_at]) if params[:start_at].present? && params[:end_at].present?

    requested_day_range
  end

  def requested_day_range
    date = account_time_zone.parse(params.fetch(:date, account_time_zone.today.to_s)).to_date
    start_at = account_time_zone.local(date.year, date.month, date.day).beginning_of_day
    start_at...start_at.next_day
  end
end
