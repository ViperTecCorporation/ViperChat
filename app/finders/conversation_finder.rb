class ConversationFinder
  attr_reader :current_user, :current_account, :params

  DEFAULT_STATUS = 'open'.freeze
  SORT_OPTIONS = {
    'last_activity_at_asc' => %w[sort_on_last_activity_at asc],
    'last_activity_at_desc' => %w[sort_on_last_activity_at desc],
    'created_at_asc' => %w[sort_on_created_at asc],
    'created_at_desc' => %w[sort_on_created_at desc],
    'priority_asc' => %w[sort_on_priority asc],
    'priority_desc' => %w[sort_on_priority desc],
    'waiting_since_asc' => %w[sort_on_waiting_since asc],
    'waiting_since_desc' => %w[sort_on_waiting_since desc],
    'priority_desc_created_at_asc' => %w[sort_on_priority_created_at desc],

    # To be removed in v3.5.0
    'latest' => %w[sort_on_last_activity_at desc],
    'sort_on_created_at' => %w[sort_on_created_at asc],
    'sort_on_priority' => %w[sort_on_priority desc],
    'sort_on_waiting_since' => %w[sort_on_waiting_since asc]
  }.with_indifferent_access
  # assumptions
  # inbox_id if not given, take from all conversations, else specific to inbox
  # assignee_type if not given, take 'all'
  # conversation_status if not given, take 'open'

  # response of this class will be of type
  # {conversations: [array of conversations], count: {open: count, resolved: count}}

  # params
  # assignee_type, inbox_id, :status

  def initialize(current_user, params)
    @current_user = current_user
    @current_account = current_user.account
    @is_admin = current_account.account_users.find_by(user_id: current_user.id)&.administrator?
    @params = params
  end

  def perform
    set_up

    mine_count, assigned_count, unassigned_count, waiting_count, group_count, all_count, internal_count =
      set_count_for_all_conversations

    filter_by_assignee_type
    filter_internal_conversations unless internal_request?

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        waiting_count: waiting_count,
        group_count: group_count,
        internal_count: internal_count,
        all_count: all_count
      }
    }
  end

  def perform_meta_only
    set_up

    mine_count, assigned_count, unassigned_count, waiting_count, group_count, all_count, internal_count =
      set_count_for_all_conversations

    {
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        waiting_count: waiting_count,
        group_count: group_count,
        internal_count: internal_count,
        all_count: all_count
      }
    }
  end

  private

  def set_up
    set_inboxes
    set_team
    set_assignee_type

    find_all_conversations
    filter_by_status unless params[:q]
    filter_by_team
    filter_by_labels
    filter_by_query
    filter_by_source_id
  end

  def set_inboxes
    @inbox_ids = if params[:inbox_id]
                   @current_user.assigned_inboxes.where(id: params[:inbox_id])
                 else
                   @current_user.assigned_inboxes.pluck(:id)
                 end
  end

  def set_assignee_type
    @assignee_type = params[:assignee_type]
  end

  def set_team
    @team = current_account.teams.find(params[:team_id]) if params[:team_id]
  end

  def find_conversation_by_inbox
    @conversations = current_account.conversations

    return unless params[:inbox_id]

    @conversations = @conversations.where(inbox_id: @inbox_ids)
  end

  def find_all_conversations
    find_conversation_by_inbox
    # Apply permission-based filtering
    @conversations = Conversations::PermissionFilterService.new(
      @conversations,
      current_user,
      current_account
    ).perform
    filter_by_conversation_type if params[:conversation_type]
    @conversations
  end

  def filter_by_assignee_type
    case @assignee_type
    when 'me'
      @conversations = @conversations.assigned_to(current_user)
    when 'unassigned'
      @conversations = @conversations.unassigned.non_group_conversations
    when 'waiting'
      @conversations = waiting_conversations
    when 'groups'
      @conversations = @conversations.group_conversations
    when 'assigned'
      @conversations = @conversations.assigned
    when 'internal'
      @conversations = @conversations.joins(:inbox)
                                     .where(inboxes: { channel_type: 'Channel::Internal' })
    end
    @conversations
  end

  def filter_by_conversation_type
    case @params[:conversation_type]
    when 'mention'
      conversation_ids = current_account.mentions.where(user: current_user).pluck(:conversation_id)
      @conversations = @conversations.where(id: conversation_ids)
    when 'participating'
      @conversations = current_user.participating_conversations.where(account_id: current_account.id)
    when 'unattended'
      @conversations = @conversations.unattended
    when 'internal'
      @conversations = @conversations.joins(:inbox)
                                     .where(inboxes: { channel_type: 'Channel::Internal' })
    end
    @conversations
  end

  def filter_internal_conversations
    @conversations = @conversations.joins(:inbox)
                                   .where.not(inboxes: { channel_type: 'Channel::Internal' })
  end

  def internal_request?
    @params[:conversation_type] == 'internal' || @assignee_type == 'internal'
  end

  def filter_by_query
    return unless params[:q]

    allowed_message_types = [Message.message_types[:incoming], Message.message_types[:outgoing]]
    @conversations = conversations.joins(:messages).where('messages.content ILIKE :search', search: "%#{params[:q]}%")
                                  .where(messages: { message_type: allowed_message_types }).includes(:messages)
                                  .where('messages.content ILIKE :search', search: "%#{params[:q]}%")
                                  .where(messages: { message_type: allowed_message_types })
  end

  def filter_by_status
    return if params[:status] == 'all'

    @conversations = @conversations.where(status: params[:status] || DEFAULT_STATUS)
  end

  def filter_by_team
    return unless @team

    @conversations = @conversations.where(team: @team)
  end

  def filter_by_labels
    return unless params[:labels]

    @conversations = @conversations.tagged_with(params[:labels], any: true)
  end

  def filter_by_source_id
    return unless params[:source_id]

    @conversations = @conversations.joins(:contact_inbox)
    @conversations = @conversations.where(contact_inboxes: { source_id: params[:source_id] })
  end

  def set_count_for_all_conversations
    status_filter = params[:status]
    status_filter = DEFAULT_STATUS if status_filter.blank?
    status_filter = nil if status_filter == 'all'

    count_scope = @conversations
    count_scope = count_scope.where(status: status_filter) if status_filter

    internal_scope = @conversations.joins(:inbox).where(inboxes: { channel_type: 'Channel::Internal' })
    internal_scope = internal_scope.where(status: status_filter) if status_filter

    unless params[:conversation_type] == 'internal' || @assignee_type == 'internal'
      count_scope = count_scope.joins(:inbox).where.not(inboxes: { channel_type: 'Channel::Internal' })
    end

    waiting_scope = count_scope.unattended
    waiting_scope = if @is_admin
                      waiting_scope
                    else
                      waiting_scope.where(assignee_id: current_user.id).or(
                        waiting_scope.where(assignee_id: nil)
                      )
                    end

    [
      count_scope.assigned_to(current_user).count,
      count_scope.assigned.count,
      count_scope.unassigned.non_group_conversations.count,
      waiting_scope.count,
      count_scope.group_conversations.count,
      count_scope.count,
      internal_scope.count
    ]
  end

  def waiting_conversations
    conversations = @conversations.unattended
    return conversations if @is_admin

    conversations.where(assignee_id: current_user.id).or(
      conversations.where(assignee_id: nil)
    )
  end

  def current_page
    page_param = params[:page]
    page = Integer(page_param)
    page.positive? ? page : 1
  rescue StandardError
    1
  end

  def conversations_base_query
    @conversations.includes(
      :inbox,
      :assignee_agent_bot,
      { assignee: { avatar_attachment: [:blob] } },
      { contact: { avatar_attachment: [:blob] } },
      :team,
      :contact_inbox
    )
  end

  def conversations
    @conversations = conversations_base_query

    sort_by, sort_order = SORT_OPTIONS[params[:sort_by]] || SORT_OPTIONS['last_activity_at_desc']
    @conversations = @conversations.send(sort_by, sort_order)

    if params[:updated_within].present?
      @conversations.where('conversations.updated_at > ?', Time.zone.now - params[:updated_within].to_i.seconds)
    else
      @conversations.page(current_page).per(ENV.fetch('CONVERSATION_RESULTS_PER_PAGE', '25').to_i)
    end
  end
end
ConversationFinder.prepend_mod_with('ConversationFinder')
