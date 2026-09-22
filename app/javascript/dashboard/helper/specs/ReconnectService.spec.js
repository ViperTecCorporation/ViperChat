import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { differenceInSeconds } from 'date-fns';
import {
  isAConversationRoute,
  isAInboxViewRoute,
  isNotificationRoute,
} from 'dashboard/helper/routeHelpers';
import ReconnectService from 'dashboard/helper/ReconnectService';

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    on: vi.fn(),
    off: vi.fn(),
    emit: vi.fn(),
  },
}));

vi.mock('date-fns', () => ({
  differenceInSeconds: vi.fn(),
}));

vi.mock('dashboard/helper/routeHelpers', () => ({
  isAConversationRoute: vi.fn(),
  isAInboxViewRoute: vi.fn(),
  isNotificationRoute: vi.fn(),
}));

const storeMock = {
  dispatch: vi.fn(),
  getters: {
    getAppliedConversationFiltersQuery: [],
    'customViews/getActiveConversationFolder': { query: {} },
    'notifications/getNotificationFilters': {},
  },
};

const routerMock = {
  currentRoute: {
    value: {
      name: '',
      params: { conversation_id: null },
    },
  },
};

describe('ReconnectService', () => {
  let reconnectService;

  beforeEach(() => {
    window.addEventListener = vi.fn();
    window.removeEventListener = vi.fn();
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: { reload: vi.fn() },
    });
    reconnectService = new ReconnectService(storeMock, routerMock);
  });

  afterEach(() => {
    reconnectService.disconnect();
    vi.clearAllMocks();
  });

  describe('constructor', () => {
    it('should initialize with store, router, and setup event listeners', () => {
      expect(reconnectService.store).toBe(storeMock);
      expect(reconnectService.router).toBe(routerMock);
      expect(window.addEventListener).toHaveBeenCalledWith(
        'online',
        reconnectService.handleOnlineEvent
      );
      expect(emitter.on).toHaveBeenCalledWith(
        BUS_EVENTS.WEBSOCKET_RECONNECT,
        reconnectService.onWebsocketReconnect
      );
      expect(emitter.on).toHaveBeenCalledWith(
        BUS_EVENTS.WEBSOCKET_DISCONNECT,
        reconnectService.onDisconnect
      );
    });
  });

  describe('disconnect', () => {
    it('should remove event listeners', () => {
      reconnectService.disconnect();
      expect(window.removeEventListener).toHaveBeenCalledWith(
        'online',
        reconnectService.handleOnlineEvent
      );
      expect(emitter.off).toHaveBeenCalledWith(
        BUS_EVENTS.WEBSOCKET_RECONNECT,
        reconnectService.onWebsocketReconnect
      );
      expect(emitter.off).toHaveBeenCalledWith(
        BUS_EVENTS.WEBSOCKET_DISCONNECT,
        reconnectService.onDisconnect
      );
    });
  });

  describe('getSecondsSinceDisconnect', () => {
    it('should return 0 if disconnectTime is null', () => {
      reconnectService.disconnectTime = null;
      expect(reconnectService.getSecondsSinceDisconnect()).toBe(0);
    });

    it('should return the number of seconds + threshold since disconnect', () => {
      reconnectService.disconnectTime = new Date();
      differenceInSeconds.mockReturnValue(100);
      expect(reconnectService.getSecondsSinceDisconnect()).toBe(100);
    });
  });

  describe('handleOnlineEvent', () => {
    it('refreshes without reloading even after a long disconnection', () => {
      reconnectService.onReconnect = vi.fn();
      reconnectService.getSecondsSinceDisconnect = vi
        .fn()
        .mockReturnValue(10801);
      reconnectService.handleOnlineEvent();
      expect(reconnectService.onReconnect).toHaveBeenCalled();
      expect(window.location.reload).not.toHaveBeenCalled();
    });

    it('should not reload the page if disconnected for less than 3 hours', () => {
      reconnectService.onReconnect = vi.fn();
      reconnectService.getSecondsSinceDisconnect = vi
        .fn()
        .mockReturnValue(10799);
      reconnectService.handleOnlineEvent();
      expect(window.location.reload).not.toHaveBeenCalled();
    });
  });

  describe('fetchConversations', () => {
    it('should update the filters with disconnected time and the threshold', async () => {
      reconnectService.getSecondsSinceDisconnect = vi.fn().mockReturnValue(100);
      await reconnectService.fetchConversations();
      expect(storeMock.dispatch).toHaveBeenCalledWith('updateChatListFilters', {
        page: 1,
        updatedWithin: null,
      });
    });

    it('should dispatch updateChatListFilters and fetchAllConversations', async () => {
      reconnectService.getSecondsSinceDisconnect = vi.fn().mockReturnValue(100);
      await reconnectService.fetchConversations();
      expect(storeMock.dispatch).toHaveBeenCalledWith('updateChatListFilters', {
        page: 1,
        updatedWithin: null,
      });
      expect(storeMock.dispatch).toHaveBeenCalledWith('fetchAllConversations', {
        refresh: true,
      });
    });

    it('should dispatch updateChatListFilters and reset updatedWithin', async () => {
      reconnectService.getSecondsSinceDisconnect = vi.fn().mockReturnValue(100);
      await reconnectService.fetchConversations();
      expect(storeMock.dispatch).toHaveBeenCalledWith('updateChatListFilters', {
        updatedWithin: null,
      });
    });
  });

  describe('fetchFilteredOrSavedConversations', () => {
    it('should dispatch fetchFilteredConversations', async () => {
      const payload = { test: 'data' };
      await reconnectService.fetchFilteredOrSavedConversations(payload);
      expect(storeMock.dispatch).toHaveBeenCalledWith(
        'fetchFilteredConversations',
        { queryData: payload, page: 1, refresh: true }
      );
    });
  });

  describe('fetchConversationsOnReconnect', () => {
    it('should fetch filtered or saved conversations if query exists', async () => {
      storeMock.getters.getAppliedConversationFiltersQuery = {
        payload: [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            values: ['open'],
          },
        ],
      };
      const spy = vi.spyOn(
        reconnectService,
        'fetchFilteredOrSavedConversations'
      );

      await reconnectService.fetchConversationsOnReconnect();

      expect(spy).toHaveBeenCalledWith(
        storeMock.getters.getAppliedConversationFiltersQuery
      );
    });

    it('should fetch all conversations if no query exists', async () => {
      storeMock.getters.getAppliedConversationFiltersQuery = [];
      storeMock.getters['customViews/getActiveConversationFolder'] = {
        query: null,
      };

      const spy = vi.spyOn(reconnectService, 'fetchConversations');

      await reconnectService.fetchConversationsOnReconnect();

      expect(spy).toHaveBeenCalled();
    });

    it('should fetch filtered or saved conversations if active folder query exists and no applied query', async () => {
      storeMock.getters.getAppliedConversationFiltersQuery = [];
      storeMock.getters['customViews/getActiveConversationFolder'] = {
        query: { test: 'activeFolderQuery' },
      };

      const spy = vi.spyOn(
        reconnectService,
        'fetchFilteredOrSavedConversations'
      );

      await reconnectService.fetchConversationsOnReconnect();

      expect(spy).toHaveBeenCalledWith({ test: 'activeFolderQuery' });
    });
  });

  describe('fetchConversationMessagesOnReconnect', () => {
    it('should dispatch syncActiveConversationMessages if conversationId exists', async () => {
      routerMock.currentRoute.value.params.conversation_id = 1;
      await reconnectService.fetchConversationMessagesOnReconnect();
      expect(storeMock.dispatch).toHaveBeenCalledWith(
        'syncActiveConversationMessages',
        { conversationId: 1, refresh: true }
      );
    });

    it('should not dispatch syncActiveConversationMessages if conversationId does not exist', async () => {
      routerMock.currentRoute.value.params.conversation_id = null;
      await reconnectService.fetchConversationMessagesOnReconnect();
      expect(storeMock.dispatch).not.toHaveBeenCalledWith(
        'syncActiveConversationMessages',
        expect.anything()
      );
    });
  });

  describe('fetchNotificationsOnReconnect', () => {
    it('should dispatch notifications/index', async () => {
      const filter = { test: 'filter' };
      await reconnectService.fetchNotificationsOnReconnect(filter);
      expect(storeMock.dispatch).toHaveBeenCalledWith('notifications/index', {
        ...filter,
        page: 1,
      });
    });
  });

  describe('revalidateCaches', () => {
    it('should dispatch revalidate actions for labels, inboxes, and teams', async () => {
      storeMock.dispatch.mockResolvedValueOnce({
        label: 'labelKey',
        inbox: 'inboxKey',
        team: 'teamKey',
      });
      await reconnectService.revalidateCaches();
      expect(storeMock.dispatch).toHaveBeenCalledWith('accounts/getCacheKeys');
      expect(storeMock.dispatch).toHaveBeenCalledWith('labels/revalidate', {
        newKey: 'labelKey',
      });
      expect(storeMock.dispatch).toHaveBeenCalledWith('inboxes/revalidate', {
        newKey: 'inboxKey',
      });
      expect(storeMock.dispatch).toHaveBeenCalledWith('teams/revalidate', {
        newKey: 'teamKey',
      });
    });
  });

  describe('handleRouteSpecificFetch', () => {
    it('should fetch conversations and messages if current route is a conversation route', async () => {
      isAConversationRoute.mockReturnValue(true);
      const spyConversations = vi.spyOn(
        reconnectService,
        'fetchConversationsOnReconnect'
      );
      const spyMessages = vi.spyOn(
        reconnectService,
        'fetchConversationMessagesOnReconnect'
      );
      await reconnectService.handleRouteSpecificFetch();
      expect(spyConversations).toHaveBeenCalled();
      expect(spyMessages).toHaveBeenCalled();
    });

    it('should fetch notifications if current route is an inbox view route', async () => {
      isAInboxViewRoute.mockReturnValue(true);
      const spy = vi.spyOn(reconnectService, 'fetchNotificationsOnReconnect');
      await reconnectService.handleRouteSpecificFetch();
      expect(spy).toHaveBeenCalled();
    });

    it('should fetch notifications if current route is a notification route', async () => {
      isNotificationRoute.mockReturnValue(true);
      const spy = vi.spyOn(reconnectService, 'fetchNotificationsOnReconnect');
      await reconnectService.handleRouteSpecificFetch();
      expect(spy).toHaveBeenCalled();
    });
  });

  describe('setConversationLastMessageId', () => {
    it('should dispatch setConversationLastMessageId if conversationId exists', async () => {
      routerMock.currentRoute.value.params.conversation_id = 1;
      await reconnectService.setConversationLastMessageId();
      expect(storeMock.dispatch).toHaveBeenCalledWith(
        'setConversationLastMessageId',
        { conversationId: 1 }
      );
    });

    it('should not dispatch setConversationLastMessageId if conversationId does not exist', async () => {
      routerMock.currentRoute.value.params.conversation_id = null;
      await reconnectService.setConversationLastMessageId();
      expect(storeMock.dispatch).not.toHaveBeenCalledWith(
        'setConversationLastMessageId',
        expect.anything()
      );
    });
  });

  describe('onDisconnect', () => {
    it('should set disconnectTime and call setConversationLastMessageId', () => {
      reconnectService.setConversationLastMessageId = vi.fn();
      reconnectService.onDisconnect();
      expect(reconnectService.disconnectTime).toBeInstanceOf(Date);
      expect(reconnectService.setConversationLastMessageId).toHaveBeenCalled();
    });
  });

  describe('onReconnect', () => {
    it('coalesces simultaneous refresh requests', async () => {
      let resolve;
      reconnectService.handleRouteSpecificFetch = vi.fn(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      reconnectService.revalidateCaches = vi.fn();
      const first = reconnectService.onReconnect();
      const second = reconnectService.onReconnect();
      expect(first).toBe(second);
      resolve();
      await first;
      expect(reconnectService.handleRouteSpecificFetch).toHaveBeenCalledTimes(
        1
      );
    });

    it('refreshes after being hidden without a websocket disconnect event', () => {
      reconnectService.onReconnect = vi.fn();
      reconnectService.hiddenAt = Date.now() - 60000;
      reconnectService.handleVisibilityChange();
      expect(reconnectService.onReconnect).toHaveBeenCalledOnce();
    });

    it('keeps the first disconnect cursor during repeated disconnect events', () => {
      reconnectService.setConversationLastMessageId = vi.fn();
      reconnectService.onDisconnect();
      const time = reconnectService.disconnectTime;
      reconnectService.onDisconnect();
      expect(reconnectService.disconnectTime).toBe(time);
      expect(
        reconnectService.setConversationLastMessageId
      ).toHaveBeenCalledOnce();
    });

    it('schedules a retry after an HTTP failure and cancels it on cleanup', async () => {
      vi.useFakeTimers();
      reconnectService.handleRouteSpecificFetch = vi
        .fn()
        .mockRejectedValue(new Error('offline'));
      await reconnectService.onReconnect();
      expect(reconnectService.retryTimer).not.toBeNull();
      reconnectService.disconnect();
      await vi.advanceTimersByTimeAsync(10000);
      expect(reconnectService.handleRouteSpecificFetch).toHaveBeenCalledOnce();
      vi.useRealTimers();
    });

    it('should handle route-specific fetch, revalidate caches, and emit WEBSOCKET_RECONNECT_COMPLETED event', async () => {
      reconnectService.handleRouteSpecificFetch = vi.fn();
      reconnectService.revalidateCaches = vi.fn();
      await reconnectService.onWebsocketReconnect();
      expect(reconnectService.handleRouteSpecificFetch).toHaveBeenCalled();
      expect(reconnectService.revalidateCaches).toHaveBeenCalled();
      expect(emitter.emit).toHaveBeenCalledWith(
        BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED
      );
    });

    it('refreshes archive and pin changes without a reconnection banner', async () => {
      reconnectService.handleRouteSpecificFetch = vi.fn();
      reconnectService.revalidateCaches = vi.fn();
      const refresh = emitter.on.mock.calls.find(
        ([name]) => name === 'refresh_conversation_list'
      )[1];
      await refresh();
      await refresh();
      expect(reconnectService.handleRouteSpecificFetch).toHaveBeenCalledTimes(
        2
      );
      expect(emitter.emit).not.toHaveBeenCalled();
    });

    it('completes a real reconnection arriving during a silent refresh', async () => {
      let resolve;
      reconnectService.handleRouteSpecificFetch = vi.fn(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      reconnectService.revalidateCaches = vi.fn();
      const refresh = reconnectService.onReconnect();
      const reconnect = reconnectService.onWebsocketReconnect();
      expect(refresh).toBe(reconnect);
      resolve();
      await refresh;
      expect(emitter.emit).toHaveBeenCalledExactlyOnceWith(
        BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED
      );
    });

    it('does not report recovery if the socket disconnects again during refresh', async () => {
      let resolve;
      reconnectService.handleRouteSpecificFetch = vi.fn(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      reconnectService.revalidateCaches = vi.fn();
      const reconnect = reconnectService.onWebsocketReconnect();
      reconnectService.onDisconnect();
      resolve();
      await reconnect;
      expect(emitter.emit).not.toHaveBeenCalled();
      expect(reconnectService.disconnectTime).not.toBeNull();
    });
  });
});
