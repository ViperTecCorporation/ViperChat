class ContactPolicy < ApplicationPolicy
  def index?
    directory_access?
  end

  def active?
    directory_access?
  end

  def import?
    @account_user.administrator? && account.feature_enabled?('data_import')
  end

  def export?
    @account_user.administrator?
  end

  def search?
    directory_access?
  end

  def filter?
    directory_access?
  end

  def update?
    show?
  end

  def contactable_inboxes?
    show?
  end

  def destroy_custom_attributes?
    show?
  end

  def show?
    return true unless record.is_a?(Contact)
    return false unless record.account_id == account.id
    return true if user.is_a?(AgentBot)
    return true if @account_user.administrator?

    visibility = Search::ConversationVisibilityService.new(current_user: user, current_account: account)
    return true unless visibility.assignment_restricted?
    return true if visibility.conversations.exists?(contact_id: record.id)

    !account.conversations.exists?(contact_id: record.id)
  end

  def create?
    true
  end

  def avatar?
    show?
  end

  def destroy?
    @account_user.administrator?
  end

  private

  def directory_access?
    return true if user.is_a?(AgentBot)

    @account_user.administrator? || !account.feature_enabled?('hide_contacts_for_agent')
  end
end

ContactPolicy.prepend_mod_with('ContactPolicy')
