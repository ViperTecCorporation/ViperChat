class NotificationBuilder
  pattr_initialize [:notification_type!, :user!, :account!, :primary_actor!, :secondary_actor]

  def perform
    build_notification
  end

  private

  def current_user
    Current.user
  end

  def user_subscribed_to_notification?
    notification_setting = user.notification_settings.find_by(account_id: account.id)
    # added for the case where an assignee might be removed from the account but remains in conversation
    return false if notification_setting.blank?

    return true if notification_setting.public_send("email_#{notification_type}?")
    return true if notification_setting.public_send("push_#{notification_type}?")

    false
  end

  def build_notification
    # Create conversation_creation notification only if user is subscribed to it
    return if notification_type == 'conversation_creation' && !user_subscribed_to_notification?
    # skip notifications for blocked conversations except for user mentions
    return if primary_actor.contact.blocked? && notification_type != 'conversation_mention'
    # respect conversation access (inbox/team membership and custom-role permissions)
    return unless user_can_access_conversation?

    existing_notification = user.notifications.find_by(
      account: account,
      primary_actor: primary_actor,
      read_at: nil
    )

    if existing_notification.present?
      new_type = notification_type
      high_priority_types = %w[
        conversation_mention
        conversation_assignment
        sla_missed_first_response
        sla_missed_next_response
        sla_missed_resolution
      ]
      if high_priority_types.include?(existing_notification.notification_type) && !high_priority_types.include?(notification_type)
        new_type = existing_notification.notification_type
      end

      existing_notification.update!(
        notification_type: new_type,
        secondary_actor: secondary_actor || current_user,
        last_activity_at: Time.current
      )

      # Trigger push notification delivery for the new message/activity
      Notification::PushNotificationJob.perform_later(existing_notification) if existing_notification.user_subscribed_to_notification?('push')

      existing_notification
    else
      user.notifications.create!(
        notification_type: notification_type,
        account: account,
        primary_actor: primary_actor,
        # secondary_actor is secondary_actor if present, else current_user
        secondary_actor: secondary_actor || current_user
      )
    end
  end

  def user_can_access_conversation?
    conversation = primary_actor.is_a?(Conversation) ? primary_actor : primary_actor.try(:conversation)
    return true if conversation.blank?

    account_user = AccountUser.find_by(account_id: account.id, user_id: user.id)
    return false if account_user.blank?

    ConversationPolicy.new(
      { user: user, account: account, account_user: account_user },
      conversation
    ).show?
  end
end
