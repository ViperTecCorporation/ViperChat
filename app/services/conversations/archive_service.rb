class Conversations::ArchiveService
  KEY = 'archived_conversations'.freeze

  def initialize(user, account)
    @user = user
    @account = account
  end

  def ids
    Array(@user.ui_settings&.dig(KEY, @account.id.to_s)).map(&:to_i).select(&:positive?).uniq
  end

  def self.archived?(user, conversation)
    return false unless conversation.is_a?(Conversation)

    new(user.reload, conversation.account).ids.include?(conversation.display_id)
  end

  def self.muted_notification?(user, conversation, notification_type)
    notification_type.to_s != 'conversation_mention' && archived?(user, conversation)
  end

  def update(conversation, archived)
    conversation.with_lock do
      raise Pundit::NotAuthorizedError if archived && conversation.assignee_id != @user.id

      @user.with_lock do
        archived_ids = ids - [conversation.display_id]
        archived_ids.unshift(conversation.display_id) if archived
        settings = @user.ui_settings || {}
        @user.update!(ui_settings: settings.merge(KEY => (settings[KEY] || {}).merge(@account.id.to_s => archived_ids)))
        archived_ids
      end
    end
  end
end
