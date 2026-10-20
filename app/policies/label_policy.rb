class LabelPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator? || (@account_user.agent? && @account.allow_agents_to_create_labels == true)
  end

  def destroy?
    @account_user.administrator?
  end
end
