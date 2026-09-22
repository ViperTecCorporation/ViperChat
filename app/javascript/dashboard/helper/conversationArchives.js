export const archivedConversationIds = (settings, accountId) =>
  (settings?.archived_conversations?.[accountId] || []).map(Number);

export const canArchiveConversation = (conversation, userId, tab) =>
  tab === 'me' &&
  conversation.meta?.assignee_type !== 'AgentBot' &&
  Number(conversation.meta?.assignee?.id ?? conversation.assignee_id) ===
    Number(userId);
