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
  
  # Trigger the notification builder logic
  pre_count = Notification.count
  Messages::NewMessageNotificationService.new(message: last_incoming_message).perform
  post_count = Notification.count
  
  processed_count += 1
  notification_count += (post_count - pre_count)
end

puts "Finished! Processed #{processed_count} conversations, created #{notification_count} notifications."
