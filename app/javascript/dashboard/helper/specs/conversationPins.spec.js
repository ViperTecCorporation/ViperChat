import {
  pinnedConversationIds,
  sortPinnedConversations,
  shouldShowConversationAssignee,
} from '../conversationPins';

describe('conversation pins', () => {
  it('isolates accounts and normalizes ids', () => {
    expect(
      pinnedConversationIds({ pinned_conversations: { 1: ['4', 3] } }, 1)
    ).toEqual([4, 3]);
    expect(
      pinnedConversationIds({ pinned_conversations: { 1: [4] } }, 2)
    ).toEqual([]);
  });
  it('puts pins first without mutating or changing the remaining order', () => {
    const conversations = [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }];
    expect(
      sortPinnedConversations(conversations, [4, 2]).map(c => c.id)
    ).toEqual([4, 2, 1, 3]);
    expect(conversations.map(c => c.id)).toEqual([1, 2, 3, 4]);
  });
  it('never inserts conversations excluded by permissions or filters', () => {
    expect(sortPinnedConversations([{ id: 1 }], [9])).toEqual([{ id: 1 }]);
  });
  it('shows the assigned agent on team conversations in Mine', () => {
    expect(
      shouldShowConversationAssignee(false, { meta: { team: { id: 4 } } })
    ).toBe(true);
    expect(shouldShowConversationAssignee(false, { team_id: 4 })).toBe(true);
    expect(shouldShowConversationAssignee(false, { meta: {} })).toBe(false);
    expect(shouldShowConversationAssignee(true, {})).toBe(true);
  });
});
