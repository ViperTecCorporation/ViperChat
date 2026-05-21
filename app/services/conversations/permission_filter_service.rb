class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    base_scope = conversations.reorder(nil)
    return base_scope if user_role == 'administrator'

    accessible_conversations(base_scope)
  end

  private

  def accessible_conversations(base_scope = conversations.reorder(nil))
    internal_inbox_ids = user.inboxes.where(account_id: account.id, channel_type: 'Channel::Internal').pluck(:id)

    internal_access_ids = Conversation
                          .joins(:inbox)
                          .where(inboxes: { id: internal_inbox_ids }, account_id: account.id)
                          .distinct
                          .pluck(:id)

    internal_participant_ids = Conversation
                               .joins(:inbox, :conversation_participants)
                               .where(inboxes: { channel_type: 'Channel::Internal' },
                                      conversation_participants: { user_id: user.id },
                                      account_id: account.id)
                               .distinct
                               .pluck(:id)

    inbox_access_ids = Conversation
                       .joins(:inbox)
                       .where.not(inboxes: { channel_type: 'Channel::Internal' })
                       .where(account_id: account.id)
                       .where(inbox: user.inboxes.where(account_id: account.id))
                       .distinct
                       .pluck(:id)

    allowed_ids = (internal_access_ids + internal_participant_ids + inbox_access_ids).uniq
    return base_scope.none if allowed_ids.empty?

    base_scope.where(id: allowed_ids)
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
