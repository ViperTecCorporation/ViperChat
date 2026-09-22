require_relative '../../../lib/conversations/history_merge'

class Conversations::SingleConversationMergeService
  include Conversations::HistoryMerge

  POLYMORPHIC = {
    'messages' => %w[sender], 'notifications' => %w[primary_actor secondary_actor],
    'active_storage_attachments' => %w[record], 'taggings' => %w[taggable tagger],
    'access_tokens' => %w[owner], 'platform_app_permissibles' => %w[permissible],
    'audits' => %w[auditable associated user], 'agent_sessions' => %w[subject result],
    'captain_assistant_responses' => %w[documentable],
    'data_import_items' => %w[chatwoot_record], 'data_import_mappings' => %w[chatwoot_record]
  }.freeze

  def initialize(inbox:, contact:)
    @inbox = inbox
    @contact = contact
  end

  def perform
    return scope.first unless @inbox.lock_to_single_conversation?
    return scope.first unless scope.offset(1).exists?

    Conversation.transaction(requires_new: true) do
      @contact.lock!
      next scope.first unless @inbox.reload.lock_to_single_conversation?

      merge_locked_conversations
    end
  rescue Conversations::HistoryMerge::Conflict, ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::LockWaitTimeout => e
    # Roll back the merge savepoint, but do not lose the incoming message.
    Rails.logger.warn("[SingleConversationMerge] skipped inbox=#{@inbox.id} contact=#{@contact.id} reason=#{e.class.name}")
    scope.first
  end

  private

  def merge_locked_conversations
    conversations = scope.lock.to_a
    target = conversations.first
    @references = history_references
    conversations.drop(1).each { |old| merge_conversation(old.id, target.id) }
    refresh_label_counters
    target
  end

  def connection
    ActiveRecord::Base.connection
  end

  def remove_conversation(id)
    # Dependents have already moved or been archived. Use a fresh instance so no stale
    # loaded association can enqueue deletion of transferred messages. Retain after-commit cache events.
    Conversation.find(id).destroy!
  end

  def scope
    @inbox.conversations.non_group_conversations.where(contact_id: @contact.id, account_id: @contact.account_id)
          .reorder(created_at: :desc, id: :desc)
  end

  def history_references
    connection.tables.flat_map do |table|
      columns = connection.columns(table).map(&:name)
      direct = columns.grep(/\A(?:target_)?conversation_id\z/).map { |column| [table, column, nil] }
      direct + POLYMORPHIC.fetch(table, []).map { |prefix| [table, "#{prefix}_id", "#{prefix}_type"] }
    end
  end
end
