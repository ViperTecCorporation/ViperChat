import actions from '../../conversations/actions';
import MessageApi from 'dashboard/api/inbox/message';
import { mutations } from '../../conversations';

vi.mock('dashboard/api/inbox/message', () => ({
  default: { getPreviousMessages: vi.fn() },
}));

describe('conversation recovery', () => {
  it('fetches every missing page and updates messages already cached', async () => {
    const state = {
      allConversations: [
        { id: 1, messages: [{ id: 1, content: 'old', created_at: 1 }] },
      ],
      syncConversationsMessages: { 1: 1 },
    };
    const commit = vi.fn();
    MessageApi.getPreviousMessages
      .mockResolvedValueOnce({
        data: {
          payload: Array.from({ length: 100 }, (_, i) => ({
            id: i + 2,
            created_at: i + 2,
          })),
        },
      })
      .mockResolvedValueOnce({
        data: { payload: [{ id: 102, created_at: 102 }] },
      })
      .mockResolvedValueOnce({
        data: {
          payload: [{ id: 1, content: 'edited', created_at: 1 }],
          meta: {},
        },
      });
    await actions.syncActiveConversationMessages(
      { state, commit, dispatch: vi.fn() },
      { conversationId: 1, refresh: true }
    );
    expect(MessageApi.getPreviousMessages).toHaveBeenNthCalledWith(2, {
      conversationId: 1,
      after: 101,
    });
    const messages = commit.mock.calls.find(
      ([type]) => type === 'SET_MISSING_MESSAGES'
    )[1].data;
    expect(messages).toHaveLength(102);
    expect(messages[0].content).toBe('edited');
  });

  it('removes stale list entries but keeps the open conversation and its draft state', () => {
    const selected = { id: 3, messages: [{ id: 5 }], dataFetched: true };
    const state = {
      selectedChatId: 3,
      allConversations: [{ id: 1 }, { id: 2 }, selected],
    };
    mutations.reconcileConversationSnapshot(state, [2]);
    expect(state.allConversations).toEqual([{ id: 2 }, selected]);
  });
});
