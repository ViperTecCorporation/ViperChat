class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'

    accessible_conversations
  end

  private

  def accessible_conversations
    internal_participant_access = conversations.joins(:inbox, :conversation_participants)
                                               .where(inboxes: { channel_type: 'Channel::Internal' },
                                                      conversation_participants: { user_id: user.id })

    inbox_access = conversations.joins(:inbox)
                                .where.not(inboxes: { channel_type: 'Channel::Internal' })
                                .where(inbox: user.inboxes.where(account_id: account.id))

    inbox_access.or(internal_participant_access).distinct
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
