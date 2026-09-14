import actions from '../../conversations/actions';
import ConversationApi from 'dashboard/api/inbox/conversation';
import MessageApi from 'dashboard/api/inbox/message';
import types from 'dashboard/store/mutation-types';
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { show: vi.fn() },
}));
vi.mock('dashboard/api/inbox/message', () => ({
  default: { getAroundMessage: vi.fn() },
}));

it('loads the original context, updates duplicates and selects the conversation', async () => {
  const commit = vi.fn();
  ConversationApi.show.mockResolvedValue({
    data: { id: 2, meta: { sender: { id: 1 } } },
  });
  MessageApi.getAroundMessage.mockResolvedValue({
    data: {
      payload: [
        { id: 10, content: 'edited', created_at: 10 },
        { id: 9, created_at: 9 },
      ],
    },
  });
  const state = {
    allConversations: [
      { id: 2, messages: [{ id: 10, content: 'old', created_at: 10 }] },
    ],
  };
  await actions.loadFavoriteMessage(
    { commit, state },
    { conversationId: 2, messageId: 10 }
  );
  expect(MessageApi.getAroundMessage).toHaveBeenCalledWith(2, 10);
  expect(commit).toHaveBeenCalledWith(types.SET_MISSING_MESSAGES, {
    id: 2,
    data: [
      { id: 9, created_at: 9 },
      { id: 10, content: 'edited', created_at: 10 },
    ],
  });
  expect(commit).toHaveBeenCalledWith(
    types.SET_CURRENT_CHAT_WINDOW,
    expect.objectContaining({ id: 2 })
  );
});
