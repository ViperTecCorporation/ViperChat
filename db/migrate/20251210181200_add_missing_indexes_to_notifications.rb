class AddMissingIndexesToNotifications < ActiveRecord::Migration[7.0]
  def change
    add_index :notifications, :user_id,
              name: 'idx_notifications_user_id',
              if_not_exists: true

    add_index :notifications, :notification_type,
              name: 'idx_notifications_notification_type',
              if_not_exists: true

    # A coluna de status de leitura é `read_at` (não existe `seen_at` no schema atual).
    add_index :notifications, :read_at,
              name: 'idx_notifications_read_at',
              if_not_exists: true
  end
end
