class MarkInternalMessagesAsRead < ActiveRecord::Migration[7.0]
  READ_STATUS = 2

  class MigrationMessage < ApplicationRecord
    self.table_name = 'messages'
  end

  class MigrationInbox < ApplicationRecord
    self.table_name = 'inboxes'
  end

  def up
    MigrationMessage.where(inbox_id: internal_inbox_ids)
                    .where('status < ?', READ_STATUS)
                    .update_all(status: READ_STATUS)
  end

  def down
    # no-op
  end

  private

  def internal_inbox_ids
    MigrationInbox.where(channel_type: 'Channel::Internal').select(:id)
  end
end
