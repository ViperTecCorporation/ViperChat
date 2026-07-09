# frozen_string_literal: true

# Rails runner script to populate notifications for existing unread conversations

puts "Starting to populate notifications for existing unread conversations..."

processed_count = 0
notification_count = 0

Conversation.where(status: :open).find_each do |conversation|
  last_incoming_message = conversation.messages.incoming.last
  next if last_incoming_message.blank?

  # Check if there are unread messages.
  # For unassigned: compare with agent_last_seen_at.
  # For assigned: compare with assignee_last_seen_at.
  has_unread = if conversation.assignee_id.present?
                 conversation.assignee_last_seen_at.nil? || last_incoming_message.created_at > conversation.assignee_last_seen_at
               else
                 conversation.agent_last_seen_at.nil? || last_incoming_message.created_at > conversation.agent_last_seen_at
               end

  next unless has_unread

  puts "Found unread conversation ##{conversation.display_id} (Inbox: #{conversation.inbox.name})"

  conversation.inbox.members.each do |member|
    next if member.id == last_incoming_message.sender_id

    # Check if they have any unread notification for this conversation
    unread_notif = Notification.find_by(
      user_id: member.id,
      primary_actor_type: 'Conversation',
      primary_actor_id: conversation.id,
      read_at: nil
    )

    if unread_notif.present?
      puts "  - User #{member.email} already has an unread notification. Updating activity."
      unread_notif.update!(
        secondary_actor: last_incoming_message,
        last_activity_at: Time.current
      )
    else
      # Check if they have a read notification for this conversation
      existing_notif = Notification.find_by(
        user_id: member.id,
        primary_actor_type: 'Conversation',
        primary_actor_id: conversation.id
      )

      if existing_notif.present?
        puts "  - User #{member.email} has a read notification. Re-opening (marking as unread)."
        existing_notif.update!(
          read_at: nil,
          secondary_actor: last_incoming_message,
          last_activity_at: Time.current
        )
        notification_count += 1
      else
        puts "  - User #{member.email} has no notification. Building new notification."
        pre_count = Notification.count
        NotificationBuilder.new(
          notification_type: 'assigned_conversation_new_message',
          user: member,
          account: conversation.account,
          primary_actor: conversation,
          secondary_actor: last_incoming_message
        ).perform
        post_count = Notification.count
        notification_count += (post_count - pre_count)
      end
    end
  end

  processed_count += 1
end

puts "Finished! Processed #{processed_count} conversations, created/re-opened #{notification_count} notifications."
