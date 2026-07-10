class Notification::MarkConversationReadService
  pattr_initialize [:user!, :account!, :conversation!]

  def perform
    return unless user.is_a?(User)

    notifications.find_each do |notification|
      notification.update!(read_at: read_at)
      # Broadcast ActionCable event for real-time Inbox sync
      Rails.configuration.dispatcher.dispatch(NOTIFICATION_UPDATED, Time.zone.now, notification: notification)
    end
  end

  private

  def notifications
    user.notifications.where(
      account: account,
      primary_actor: conversation,
      read_at: nil
    )
  end

  def read_at
    @read_at ||= Time.current
  end
end
