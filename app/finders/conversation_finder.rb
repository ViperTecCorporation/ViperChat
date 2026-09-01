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
    'unread' => %w[sort_on_unread desc],

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
    @conversations = if params[:q]
                       Search::ConversationVisibilityService.new(
                         current_user: current_user,
                         current_account: current_account
                       ).conversations.merge(@conversations)
                     else
                       Conversations::PermissionFilterService.new(
                         @conversations,
                         current_user,
                         current_account
                       ).perform
                     end
    filter_by_conversation_type if params[:conversation_type]
    @conversations
  end

  def filter_by_assignee_type
    case @assignee_type
    when 'me'
      @conversations = mine_conversations(@conversations)
    when 'unassigned'
      @conversations = unassigned_conversations(@conversations)
    when 'waiting'
      @conversations = waiting_conversations
    when 'groups'
      @conversations = @conversations.group_conversations
    when 'assigned'
      @conversations = assigned_conversations(@conversations)
    when 'internal'
      @conversations = @conversations.where(inbox_id: internal_inbox_scope)
    end
    @conversations = @conversations.non_group_conversations unless %w[me groups].include?(@assignee_type)
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
      @conversations = @conversations.where(inbox_id: internal_inbox_scope)
    end
    @conversations
  end

  def filter_internal_conversations
    @conversations = @conversations.where.not(inbox_id: internal_inbox_scope)
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

    internal_scope = @conversations.where(inbox_id: internal_inbox_scope)
    internal_scope = internal_scope.where(status: status_filter) if status_filter

    unless params[:conversation_type] == 'internal' || @assignee_type == 'internal'
      count_scope = count_scope.where.not(inbox_id: internal_inbox_scope)
    end

    waiting_scope = count_scope.non_group_conversations.unattended
    waiting_scope = if @is_admin
                      waiting_scope
                    else
                      waiting_scope.where(assignee_id: current_user.id).or(
                        waiting_scope.where(assignee_id: nil)
                      )
                    end

    return legacy_count_for_all_conversations(count_scope, internal_scope, waiting_scope) if count_scope.limit_value || count_scope.offset_value || count_scope.eager_loading?

    waiting_filter = '"conversations"."group" = FALSE AND (first_reply_created_at IS NULL OR waiting_since IS NOT NULL)'
    waiting_filter = "#{waiting_filter} AND (assignee_id = #{current_user.id} OR assignee_id IS NULL)" unless @is_admin

    counts = count_scope.unscope(:order).pick(
      Arel.sql("COUNT(*) FILTER (WHERE #{mine_count_filter})"),
      Arel.sql('COUNT(*) FILTER (WHERE "conversations"."group" = FALSE AND (assignee_id IS NOT NULL OR team_id IS NOT NULL))'),
      Arel.sql('COUNT(*) FILTER (WHERE "conversations"."group" = FALSE AND assignee_id IS NULL AND team_id IS NULL)'),
      Arel.sql("COUNT(*) FILTER (WHERE #{waiting_filter})"),
      Arel.sql('COUNT(*) FILTER (WHERE "conversations"."group" = TRUE)'),
      Arel.sql('COUNT(*) FILTER (WHERE "conversations"."group" = FALSE)')
    )
    counts = counts || [0, 0, 0, 0, 0, 0]
    counts + [internal_scope.count]
  end

  def legacy_count_for_all_conversations(count_scope, internal_scope, waiting_scope)
    [
      mine_conversations(count_scope).count,
      assigned_conversations(count_scope).count,
      unassigned_conversations(count_scope).count,
      waiting_scope.count,
      count_scope.group_conversations.count,
      count_scope.non_group_conversations.count,
      internal_scope.count
    ]
  end

  def waiting_conversations
    conversations = @conversations.non_group_conversations.unattended
    return conversations if @is_admin

    conversations.where(assignee_id: current_user.id).or(
      conversations.where(assignee_id: nil)
    )
  end

  def mine_conversations(scope)
    conversations_assigned_to_user = scope.where(assignee_id: current_user.id)
    return conversations_assigned_to_user unless current_account.include_team_conversations_in_mine?

    conversations_assigned_to_user.or(scope.where(team_id: current_user_team_ids))
  end

  def assigned_conversations(scope)
    non_group_conversations = scope.non_group_conversations
    non_group_conversations.where.not(assignee_id: nil).or(non_group_conversations.where.not(team_id: nil))
  end

  def unassigned_conversations(scope)
    scope.where(assignee_id: nil, team_id: nil).non_group_conversations
  end

  def mine_count_filter
    filter = "conversations.assignee_id = #{current_user.id}"
    return filter unless current_account.include_team_conversations_in_mine?
    return filter if current_user_team_ids.empty?

    "#{filter} OR conversations.team_id IN (#{current_user_team_ids.join(', ')})"
  end

  def current_user_team_ids
    @current_user_team_ids ||= current_user.teams.where(account_id: current_account.id).pluck(:id)
  end

  def internal_inbox_scope
    current_account.inboxes.where(channel_type: 'Channel::Internal').select(:id)
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
