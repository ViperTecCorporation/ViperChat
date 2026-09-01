class Search::ConversationVisibilityService
  pattr_initialize [:current_user!, :current_account!]

  def conversations
    @conversations ||= apply_agent_flags(permission_scope)
  end

  def contacts(contacts_query)
    return contacts_query if account_user.administrator?
    return Contact.none if current_account.feature_enabled?('hide_contacts_for_agent')

    visible_contact_ids = conversations.select(:contact_id)
    contact_ids_with_conversations = current_account.conversations.select(:contact_id)

    contacts_query.where(id: visible_contact_ids).or(
      contacts_query.where.not(id: contact_ids_with_conversations)
    )
  end

  def assignment_restricted?
    return false if account_user.administrator?

    current_account.feature_enabled?('hide_all_chats_for_agent') ||
      current_account.feature_enabled?('hide_unassigned_for_agent')
  end

  private

  def permission_scope
    Conversations::PermissionFilterService.new(
      current_account.conversations,
      current_user,
      current_account
    ).perform
  end

  def apply_agent_flags(scope)
    return scope if account_user.administrator?
    return hide_unassigned_conversations(scope) unless current_account.feature_enabled?('hide_all_chats_for_agent')

    visible_scope = mine_conversations(scope)
    return visible_scope if current_account.feature_enabled?('hide_unassigned_for_agent')

    visible_scope.or(scope.where(assignee_id: nil, team_id: nil))
  end

  def hide_unassigned_conversations(scope)
    return scope unless current_account.feature_enabled?('hide_unassigned_for_agent')

    scope.where.not(assignee_id: nil).or(scope.where.not(team_id: nil))
  end

  def mine_conversations(scope)
    mine_scope = scope.where(assignee_id: current_user.id)
    return mine_scope unless current_account.include_team_conversations_in_mine?

    team_ids = current_user.teams.where(account_id: current_account.id).select(:id)
    mine_scope.or(scope.where(team_id: team_ids))
  end

  def account_user
    @account_user ||= current_account.account_users.find_by!(user: current_user)
  end
end
