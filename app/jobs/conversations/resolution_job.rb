class Conversations::ResolutionJob < ApplicationJob
  queue_as :low

  def perform(account:)
    # limiting the number of conversations to be resolved to avoid any performance issues
    resolvable_conversations = conversation_scope(account).limit(Limits::BULK_ACTIONS_LIMIT)
    resolvable_conversations.each do |conversation|
      # send message from bot that conversation has been resolved
      # do this is account.auto_resolve_message is set
      ::MessageTemplates::Template::AutoResolve.new(conversation: conversation).perform if account.auto_resolve_message.present?
      conversation.add_labels(account.auto_resolve_label) if account.auto_resolve_label.present?
      conversation.toggle_status
    end
  end

  private

  def conversation_scope(account)
    base_scope = if account.auto_resolve_ignore_waiting
                   account.conversations.resolvable_not_waiting(account.auto_resolve_after)
                 else
                   account.conversations.resolvable_all(account.auto_resolve_after)
                 end
    base_scope = apply_inbox_scope(base_scope, account)
    # Exclude orphan conversations where contact was deleted but conversation cleanup is pending
    base_scope.where.not(contact_id: nil)
  end

  def apply_inbox_scope(scope, account)
    rules = auto_resolve_inbox_rules(account)
    return scope.non_group_conversations if rules.blank?

    regular_inbox_ids = rules.keys
    group_inbox_ids = rules.select { |_inbox_id, send_to_groups| send_to_groups }.keys

    scope.where(inbox_id: regular_inbox_ids, group: false)
         .or(scope.where(inbox_id: group_inbox_ids, group: true))
  end

  def auto_resolve_inbox_rules(account)
    rules = Array(account.auto_resolve_inboxes).filter_map do |rule|
      inbox_id = Integer(rule['inbox_id'] || rule[:inbox_id], exception: false)
      next if inbox_id.blank?

      [inbox_id, ActiveModel::Type::Boolean.new.cast(rule['send_to_groups'] || rule[:send_to_groups])]
    end.to_h
    return rules if rules.present?

    Array(account.settings&.[]('auto_resolve_inbox_ids')).filter_map do |inbox_id|
      normalized_inbox_id = Integer(inbox_id, exception: false)
      if normalized_inbox_id
        [normalized_inbox_id, ActiveModel::Type::Boolean.new.cast(account.settings&.[]('auto_resolve_send_to_groups'))]
      end
    end.to_h
  end
end
