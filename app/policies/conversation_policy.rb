class ConversationPolicy < ApplicationPolicy
  def index?
    true
  end

  def destroy?
    administrator?
  end

  def show?
    return false unless record.account_id == account&.id
    return true if administrator? || agent_bot? || participant_access?

    assignment_visible? && agent_can_view_conversation?
  end

  def delete_message?
    show? && (administrator? || agent_bot? || !account.feature_enabled?('hide_delete_message_for_agent'))
  end

  private

  def assignment_visible?
    return false unless account_user

    Search::ConversationVisibilityService.new(current_user: user, current_account: account).allows_assignment?(record)
  end

  def agent_can_view_conversation?
    inbox_access? || team_access?
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def inbox_access?
    user.inboxes.where(account_id: account&.id).exists?(id: record.inbox_id)
  end

  def team_access?
    return false if record.team_id.blank?

    user.teams.where(account_id: account&.id).exists?(id: record.team_id)
  end

  def assigned_to_user?
    record.assignee_id == user.id
  end

  def participant?
    record.conversation_participants.exists?(user_id: user.id)
  end

  def participant_access?
    return false unless participant?

    record.inbox.internal_chat?
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
