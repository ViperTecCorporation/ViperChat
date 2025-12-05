class InboxPolicy < ApplicationPolicy
  class Scope
    attr_reader :user_context, :user, :scope, :account, :account_user

    def initialize(user_context, scope)
      @user_context = user_context
      @user = user_context[:user]
      @account = user_context[:account]
      @account_user = user_context[:account_user]
      @scope = scope
    end

    def resolve
      base_scope = scope
                    .reorder(nil)
                    .where(account_id: account.id)
                    .unscope(:includes)
                    .preload(nil)
                    .eager_load(nil)
                    .includes(nil) # remove any inherited eager loads that might include polymorphic :channel

      # Admins visualizam todas as inboxes da conta.
      return base_scope if account_user&.administrator?

      assigned_ids = user.assigned_inboxes.where(account_id: account.id).pluck(:id)
      internal_ids = scope.where(account_id: account.id, channel_type: 'Channel::Internal').pluck(:id)
      allowed_ids = (assigned_ids + internal_ids).uniq

      base_scope.where(id: allowed_ids)
    end
  end

  def index?
    true
  end

  def show?
    # FIXME: for agent bots, lets bring this validation to policies as well in future
    return true if @user.is_a?(AgentBot)
    return true if record.internal_chat? && @account_user.present?

    Current.user.assigned_inboxes.include? record
  end

  def assignable_agents?
    true
  end

  def agent_bot?
    true
  end

  def campaigns?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def set_agent_bot?
    @account_user.administrator?
  end

  def avatar?
    @account_user.administrator?
  end

  def sync_templates?
    @account_user.administrator?
  end

  def health?
    @account_user.administrator?
  end
end
