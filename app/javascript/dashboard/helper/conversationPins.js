export const pinnedConversationIds = (settings, accountId) =>
  (settings?.pinned_conversations?.[accountId] || []).map(Number).slice(0, 3);

export const sortPinnedConversations = (conversations, pins) => {
  const rank = id => {
    const index = pins.indexOf(Number(id));
    return index < 0 ? pins.length : index;
  };
  return [...conversations].sort((a, b) => rank(a.id) - rank(b.id));
};

export const shouldShowConversationAssignee = (showAssignee, conversation) =>
  showAssignee || !!conversation.meta?.team?.id || !!conversation.team_id;
