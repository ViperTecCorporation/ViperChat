class Messages::MentionService
  pattr_initialize [:message!]

  def perform
    return unless valid_mention_message?(message)

    validated_mentioned_ids = accessible_mentioned_ids
    return if validated_mentioned_ids.blank?

    Conversations::UserMentionJob.perform_later(validated_mentioned_ids, message.conversation.id, message.account.id)
    add_mentioned_users_as_participants(validated_mentioned_ids)
    generate_notifications_for_mentions(validated_mentioned_ids)
  end

  private

  def valid_mention_message?(message)
    (message.private? || internal_agent_message?) && message.content.present? && mentioned_ids.present?
  end

  def internal_agent_message?
    message.inbox.internal_chat? && message.sender_type == 'User' &&
      message.account.account_users.exists?(user_id: message.sender_id)
  end

  def mentioned_ids
    user_mentions = message.content.scan(%r{\(mention://user/(\d+)/(.+?)\)}).map(&:first)
    team_mentions = message.content.scan(%r{\(mention://team/(\d+)/(.+?)\)}).map(&:first)

    expanded_user_ids = expand_team_mentions_to_users(team_mentions)

    (user_mentions + expanded_user_ids).uniq
  end

  def expand_team_mentions_to_users(team_ids)
    return [] if team_ids.blank?

    message.inbox.account.teams
           .joins(:team_members)
           .where(id: team_ids)
           .pluck('team_members.user_id')
           .map(&:to_s)
  end

  def accessible_mentioned_ids
    message.account.account_users.includes(:user).where(user_id: mentioned_ids).filter_map do |account_user|
      # Check access before adding participants: a mention must not grant access by itself.
      context = { user: account_user.user, account: message.account, account_user: account_user }
      account_user.user_id.to_s if ConversationPolicy.new(context, message.conversation).show?
    end
  end

  def generate_notifications_for_mentions(validated_mentioned_ids)
    validated_mentioned_ids.each do |user_id|
      next if self_mention?(user_id)

      NotificationBuilder.new(
        notification_type: 'conversation_mention',
        user: User.find(user_id),
        account: message.account,
        primary_actor: message.conversation,
        secondary_actor: message
      ).perform
    end
  end

  def self_mention?(user_id)
    message.sender_type == 'User' && user_id.to_i == message.sender_id
  end

  def add_mentioned_users_as_participants(validated_mentioned_ids)
    validated_mentioned_ids.each do |user_id|
      message.conversation.conversation_participants.find_or_create_by(user_id: user_id)
    end
  end
end
