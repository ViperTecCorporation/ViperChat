class Conversations::FilterService < FilterService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze
  UNASSIGNED_FILTER_OPERATORS = %w[equal_to not_equal_to].freeze

  def initialize(params, user, account)
    @account = account
    super(params, user)
  end

  def perform
    normalize_unassigned_assignee_filter
    restrict_assignee_filter_to_current_user
    validate_query_operator
    @conversations = query_builder(@filters['conversations'])
    mine_count, unassigned_count, group_count, all_count, = set_count_for_all_conversations
    assigned_count = all_count - unassigned_count

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        group_count: group_count,
        all_count: all_count
      }
    }
  end

  def base_relation
    conversations = @account.conversations.includes(
      :taggings, :inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team, :messages, :contact_inbox
    )
    conversations = conversations.non_group_conversations if filtering_unassigned_assignee?

    Conversations::PermissionFilterService.new(
      conversations,
      @user,
      @account
    ).perform
  end

  def current_page
    @params[:page] || 1
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def conversations
    @conversations.sort_on_last_activity_at.page(current_page)
  end

  private

  def filtering_unassigned_assignee?
    @params[:payload].any? do |filter|
      filter[:attribute_key] == 'assignee_id' && filter[:filter_operator] == 'is_not_present'
    end
  end

  def normalize_unassigned_assignee_filter
    @params[:payload].each do |filter|
      next unless filter[:attribute_key] == 'assignee_id'
      next unless filter[:values] == ['nil']
      next unless UNASSIGNED_FILTER_OPERATORS.include?(filter[:filter_operator])

      filter[:filter_operator] = filter[:filter_operator] == 'equal_to' ? 'is_not_present' : 'is_present'
      filter[:values] = []
    end
  end

  def restrict_assignee_filter_to_current_user
    return unless @account.feature_enabled?('restrict_assignee_filter_for_agent')
    return if @account.account_users.find_by!(user_id: @user.id).administrator?

    @params[:payload].each do |filter|
      next unless filter[:attribute_key] == 'assignee_id'

      filter[:filter_operator] = 'equal_to'
      filter[:values] = [@user.id]
    end
  end
end
