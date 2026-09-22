import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { differenceInSeconds } from 'date-fns';
import {
  isAConversationRoute,
  isAInboxViewRoute,
  isNotificationRoute,
} from 'dashboard/helper/routeHelpers';

const BACKGROUND_REFRESH_MS = 30000;

class ReconnectService {
  constructor(store, router) {
    this.store = store;
    this.router = router;
    this.disconnectTime = null;
    this.hiddenAt = null;
    this.inFlight = null;
    this.disposed = false;
    this.retryTimer = null;
    this.reconnectPending = false;

    this.setupEventListeners();
  }

  disconnect = () => {
    this.disposed = true;
    clearTimeout(this.retryTimer);
    this.nativeListener?.remove();
    this.removeEventListeners();
  };

  setupEventListeners = () => {
    window.addEventListener('online', this.handleOnlineEvent);
    document.addEventListener('visibilitychange', this.handleVisibilityChange);
    window.addEventListener('pageshow', this.handlePageShow);
    emitter.on('refresh_conversation_list', this.onReconnect);
    if (window.chatwootConfig?.isNativeApp) {
      import('@capacitor/app').then(async ({ App }) => {
        const listener = await App.addListener(
          'appStateChange',
          ({ isActive }) => {
            if (isActive) this.onReconnect();
            else this.onDisconnect();
          }
        );
        if (this.disposed) listener.remove();
        else this.nativeListener = listener;
      });
    }
    emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, this.onWebsocketReconnect);
    emitter.on(BUS_EVENTS.WEBSOCKET_DISCONNECT, this.onDisconnect);
  };

  removeEventListeners = () => {
    window.removeEventListener('online', this.handleOnlineEvent);
    document.removeEventListener(
      'visibilitychange',
      this.handleVisibilityChange
    );
    window.removeEventListener('pageshow', this.handlePageShow);
    emitter.off('refresh_conversation_list', this.onReconnect);
    emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, this.onWebsocketReconnect);
    emitter.off(BUS_EVENTS.WEBSOCKET_DISCONNECT, this.onDisconnect);
  };

  getSecondsSinceDisconnect = () =>
    this.disconnectTime
      ? Math.max(differenceInSeconds(new Date(), this.disconnectTime), 0)
      : 0;

  handleOnlineEvent = () => this.onReconnect();

  handlePageShow = event => {
    if (event.persisted) this.onReconnect();
  };

  handleVisibilityChange = () => {
    if (document.hidden) {
      this.hiddenAt = Date.now();
      this.setConversationLastMessageId();
    } else if (
      this.disconnectTime ||
      (this.hiddenAt !== null &&
        Date.now() - this.hiddenAt >= BACKGROUND_REFRESH_MS)
    ) {
      this.hiddenAt = null;
      this.onReconnect();
    }
  };

  fetchConversations = async () => {
    await this.store.dispatch('updateChatListFilters', {
      page: 1,
      updatedWithin: null,
    });
    await this.store.dispatch('conversationPage/reset');
    await this.store.dispatch('fetchAllConversations', { refresh: true });
    // Reset the updatedWithin in the store chat list filter after fetching conversations when the user is reconnected
    await this.store.dispatch('updateChatListFilters', {
      updatedWithin: null,
    });
  };

  fetchFilteredOrSavedConversations = async queryData => {
    await this.store.dispatch('conversationPage/reset');
    await this.store.dispatch('fetchFilteredConversations', {
      queryData,
      page: 1,
      refresh: true,
    });
  };

  fetchConversationsOnReconnect = async () => {
    const {
      getAppliedConversationFiltersQuery,
      'customViews/getActiveConversationFolder': activeFolder,
    } = this.store.getters;
    const query = getAppliedConversationFiltersQuery?.payload?.length
      ? getAppliedConversationFiltersQuery
      : activeFolder?.query;
    if (query) {
      await this.fetchFilteredOrSavedConversations(query);
    } else {
      await this.fetchConversations();
    }
  };

  fetchConversationMessagesOnReconnect = async () => {
    const { conversation_id: conversationId } =
      this.router.currentRoute.value.params;
    if (conversationId) {
      await this.store.dispatch('syncActiveConversationMessages', {
        conversationId: Number(conversationId),
        refresh: true,
      });
    }
  };

  fetchNotificationsOnReconnect = async filter => {
    await this.store.dispatch('notifications/index', { ...filter, page: 1 });
  };

  revalidateCaches = async () => {
    const { label, inbox, team } = await this.store.dispatch(
      'accounts/getCacheKeys'
    );
    await Promise.all([
      this.store.dispatch('labels/revalidate', { newKey: label }),
      this.store.dispatch('inboxes/revalidate', { newKey: inbox }),
      this.store.dispatch('teams/revalidate', { newKey: team }),
    ]);
  };

  handleRouteSpecificFetch = async () => {
    await this.store.dispatch('syncConversationArchives');
    const currentRoute = this.router.currentRoute.value.name;
    if (isAConversationRoute(currentRoute, true)) {
      await Promise.all([
        this.fetchConversationsOnReconnect(),
        this.fetchConversationMessagesOnReconnect(),
      ]);
    } else if (isAInboxViewRoute(currentRoute, true)) {
      await this.fetchNotificationsOnReconnect(
        this.store.getters['notifications/getNotificationFilters']
      );
      await this.fetchConversationMessagesOnReconnect();
    } else if (isNotificationRoute(currentRoute)) {
      await this.fetchNotificationsOnReconnect();
    }
  };

  setConversationLastMessageId = async () => {
    const { conversation_id: conversationId } =
      this.router.currentRoute.value.params;
    if (conversationId) {
      await this.store.dispatch('setConversationLastMessageId', {
        conversationId: Number(conversationId),
      });
    }
  };

  onDisconnect = () => {
    this.reconnectPending = false;
    if (this.disconnectTime) return;
    this.disconnectTime = new Date();
    this.setConversationLastMessageId();
  };

  onWebsocketReconnect = () => {
    this.reconnectPending = true;
    return this.onReconnect();
  };

  onReconnect = () => {
    if (this.disposed || navigator.onLine === false || document.hidden)
      return Promise.resolve();
    if (this.inFlight) return this.inFlight;
    clearTimeout(this.retryTimer);
    this.inFlight = (async () => {
      try {
        await this.handleRouteSpecificFetch();
        if (this.disposed) return;
        await this.revalidateCaches();
        if (this.disposed) return;
        // List refreshes (archive, pin, pull-to-refresh) are not socket events.
        if (this.reconnectPending) {
          this.reconnectPending = false;
          this.disconnectTime = null;
          emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED);
        }
      } catch (error) {
        if (!this.disposed)
          this.retryTimer = setTimeout(this.onReconnect, 10000);
      } finally {
        this.inFlight = null;
      }
    })();
    return this.inFlight;
  };
}

export default ReconnectService;
