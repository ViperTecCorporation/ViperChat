import actions from 'dashboard/store/modules/conversations/actions';
import { mutations } from 'dashboard/store/modules/conversations';
import MessageApi from 'dashboard/api/inbox/message';
import types from 'dashboard/store/mutation-types';

vi.mock('dashboard/api/inbox/message', () => ({
  default: { getPreviousMessages: vi.fn() },
}));

describe('cached conversation reconciliation', () => {
  beforeEach(() => vi.clearAllMocks());
  it('refreshes cached messages even when conversation metadata already arrived', async () => {
    const state = {
      selectedChatId: 1,
      allConversations: [
        {
          id: 1,
          messages: [{ id: 10 }],
          isCachedSnapshot: true,
          hasCachedMessages: true,
          dataFetched: true,
        },
      ],
    };
    mutations[types.UPDATE_CONVERSATION](state, {
      id: 1,
      isCachedSnapshot: false,
    });
    expect(state.allConversations[0].hasCachedMessages).toBe(true);
    const dispatch = vi.fn().mockResolvedValue();
    await actions.setActiveChat(
      { commit: vi.fn(), dispatch },
      { data: state.allConversations[0] }
    );
    expect(dispatch).toHaveBeenCalledWith('syncActiveConversationMessages', {
      conversationId: 1,
      refresh: true,
    });
  });

  it('preserves the pending message verification marker when a selected list row is refreshed', () => {
    const state = {
      selectedChatId: 1,
      allConversations: [
        {
          id: 1,
          messages: [{ id: 10 }],
          hasCachedMessages: true,
          dataFetched: true,
        },
      ],
    };
    mutations[types.SET_ALL_CONVERSATION](state, [
      { id: 1, messages: [{ id: 20 }] },
    ]);
    expect(state.allConversations[0].messages).toEqual([{ id: 10 }]);
    expect(state.allConversations[0].hasCachedMessages).toBe(true);
  });

  it('merges edits and repeated server deliveries by ID without duplicate bubbles before allowing changes', async () => {
    const state = {
      syncConversationsMessages: {},
      selectedChatId: 1,
      allConversations: [
        {
          id: 1,
          hasCachedMessages: true,
          messages: [{ id: 10, content: 'SYNTHETIC old', created_at: 1 }],
        },
      ],
    };
    MessageApi.getPreviousMessages.mockResolvedValueOnce({
      data: { payload: [] },
    });
    MessageApi.getPreviousMessages.mockResolvedValueOnce({
      data: {
        meta: {},
        payload: [
          { id: 10, content: 'SYNTHETIC edited', created_at: 1 },
          { id: 10, content: 'SYNTHETIC edited', created_at: 1 },
          { id: 11, content: 'SYNTHETIC new', created_at: 2 },
        ],
      },
    });
    const commit = (type, payload) => mutations[type]?.(state, payload);
    await actions.syncActiveConversationMessages(
      { commit, state, dispatch: vi.fn(), rootGetters: {} },
      { conversationId: 1, refresh: true }
    );
    expect(
      state.allConversations[0].messages.map(message => message.id)
    ).toEqual([10, 11]);
    expect(state.allConversations[0].messages[0].content).toBe(
      'SYNTHETIC edited'
    );
    expect(state.allConversations[0].hasCachedMessages).toBe(false);
  });

  it('drops unverified list entries but keeps the selected cached row read-only until its detail request authorizes it', () => {
    const state = {
      selectedChatId: 1,
      allConversations: [
        { id: 1, isCachedSnapshot: true },
        { id: 2, isCachedSnapshot: true },
        { id: 3 },
      ],
    };
    mutations.reconcileCachedConversationSnapshot(state, []);
    expect(state.allConversations.map(chat => chat.id)).toEqual([1, 3]);
  });

  it.each([
    ['delivered', 'progress'],
    ['delivered', 'sent'],
    ['read', 'progress'],
    ['read', 'sent'],
    ['read', 'delivered'],
  ])(
    'does not replace a concurrent %s receipt with an older HTTP %s receipt',
    async (receipt, staleStatus) => {
      const original = {
        id: 10,
        conversation_id: 1,
        content: 'SYNTHETIC',
        created_at: 1,
        status: 'progress',
        source_id: null,
      };
      const state = {
        syncConversationsMessages: {},
        selectedChatId: 1,
        allConversations: [
          { id: 1, hasCachedMessages: true, messages: [original] },
        ],
      };
      let resolveResponse;
      MessageApi.getPreviousMessages.mockResolvedValueOnce({
        data: { payload: [] },
      });
      MessageApi.getPreviousMessages.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveResponse = resolve;
          })
      );
      const commit = (type, payload) => mutations[type]?.(state, payload);
      const refresh = actions.syncActiveConversationMessages(
        { commit, state, dispatch: vi.fn(), rootGetters: {} },
        { conversationId: 1, refresh: true }
      );
      await vi.waitFor(() => expect(resolveResponse).toBeTypeOf('function'));
      mutations[types.ADD_MESSAGE](state, {
        ...original,
        status: receipt,
        source_id: 'synthetic-provider-id',
      });
      resolveResponse({
        data: { meta: {}, payload: [{ ...original, status: staleStatus }] },
      });
      await refresh;

      expect(state.allConversations[0].messages).toEqual([
        { ...original, status: receipt, source_id: 'synthetic-provider-id' },
      ]);
      expect(state.allConversations[0].hasCachedMessages).toBe(false);
    }
  );

  it('still replaces a stale cached receipt with the authoritative server failure', async () => {
    const original = { id: 10, status: 'sent', source_id: null, created_at: 1 };
    const state = {
      syncConversationsMessages: {},
      allConversations: [
        { id: 1, hasCachedMessages: true, messages: [original] },
      ],
    };
    MessageApi.getPreviousMessages.mockResolvedValueOnce({
      data: { payload: [] },
    });
    MessageApi.getPreviousMessages.mockResolvedValueOnce({
      data: {
        meta: {},
        payload: [
          {
            ...original,
            status: 'failed',
            content_attributes: { external_error: 'HTTP 502' },
          },
        ],
      },
    });
    await actions.syncActiveConversationMessages(
      {
        commit: (type, payload) => mutations[type]?.(state, payload),
        state,
        dispatch: vi.fn(),
      },
      { conversationId: 1, refresh: true }
    );
    expect(state.allConversations[0].messages[0]).toMatchObject({
      status: 'failed',
      content_attributes: { external_error: 'HTTP 502' },
    });
  });

  it('does not treat an unvalidated cached read receipt as newer than the server', async () => {
    const state = {
      syncConversationsMessages: {},
      allConversations: [
        {
          id: 1,
          hasCachedMessages: true,
          messages: [
            {
              id: 10,
              status: 'read',
              source_id: 'old-cache-id',
              created_at: 1,
            },
          ],
        },
      ],
    };
    const serverMessage = {
      id: 10,
      status: 'sent',
      source_id: 'server-id',
      created_at: 1,
    };
    MessageApi.getPreviousMessages.mockResolvedValueOnce({
      data: { payload: [] },
    });
    MessageApi.getPreviousMessages.mockResolvedValueOnce({
      data: { meta: {}, payload: [serverMessage] },
    });
    await actions.syncActiveConversationMessages(
      {
        commit: (type, payload) => mutations[type]?.(state, payload),
        state,
        dispatch: vi.fn(),
      },
      { conversationId: 1, refresh: true }
    );
    expect(state.allConversations[0].messages).toEqual([serverMessage]);
  });

  it('deduplicates overlapping history pages against cached messages, keeping the server update', () => {
    const state = {
      allConversations: [
        {
          id: 1,
          messages: [{ id: 10, content: 'SYNTHETIC cached', created_at: 1 }],
        },
      ],
    };
    const data = [
      { id: 10, content: 'SYNTHETIC server', created_at: 1 },
      { id: 10, content: 'SYNTHETIC server', created_at: 1 },
    ];
    mutations[types.SET_PREVIOUS_CONVERSATIONS](state, { id: 1, data });
    mutations[types.SET_PREVIOUS_CONVERSATIONS](state, { id: 1, data });
    expect(state.allConversations[0].messages).toEqual([
      { id: 10, content: 'SYNTHETIC server', created_at: 1 },
    ]);
  });
});
