import {
  archivedConversationIds,
  canArchiveConversation,
} from '../conversationArchives';
import AudioNotificationStore from '../AudioAlerts/AudioNotificationStore';

describe('personal conversation archives', () => {
  const conversation = {
    id: 7,
    meta: { assignee: { id: 3 }, team: { id: 9 } },
  };
  it('allows only mine and a direct assignment to the current agent', () => {
    expect(canArchiveConversation(conversation, 3, 'me')).toBe(true);
    expect(canArchiveConversation(conversation, 4, 'me')).toBe(false);
    expect(canArchiveConversation(conversation, 3, 'all')).toBe(false);
    expect(canArchiveConversation({ meta: { team: { id: 9 } } }, 3, 'me')).toBe(
      false
    );
    expect(
      canArchiveConversation(
        {
          ...conversation,
          meta: { ...conversation.meta, assignee_type: 'AgentBot' },
        },
        3,
        'me'
      )
    ).toBe(false);
  });
  it('isolates archive IDs by account', () => {
    const settings = { archived_conversations: { 1: ['7'], 2: [8] } };
    expect(archivedConversationIds(settings, 1)).toEqual([7]);
    expect(archivedConversationIds(settings, 3)).toEqual([]);
  });
  it('excludes archived unread conversations from recurring audio alerts', () => {
    const store = {
      getters: {
        getUISettings: { archived_conversations: { 1: [7] } },
        getCurrentAccountId: 1,
        getMineChats: () => [{ id: 7, unread_count: 2 }],
      },
    };
    const audio = new AudioNotificationStore(store);
    expect(audio.isArchived(7)).toBe(true);
    expect(audio.hasUnreadConversation()).toBe(false);
    store.getters.getUISettings.archived_conversations[1] = [];
    expect(audio.hasUnreadConversation()).toBe(true);
  });
});
