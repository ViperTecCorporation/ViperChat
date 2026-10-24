import { reactive } from 'vue';
import { openDB } from 'idb';
import { offlineOutbox } from './offlineOutbox';
import {
  CACHE_DB,
  CACHE_TTL,
  CACHE_EPOCH_KEY,
  cacheEpoch,
  buildSnapshot,
  cacheScope,
  restoreSnapshot,
  clearSnapshotView,
} from './frontendSnapshot';

export const cacheMutations = {
  restoreFrontendSnapshot: restoreSnapshot,
  clearFrontendSnapshot: clearSnapshotView,
  restoreCachedConversations(state, rows) {
    state.conversations.allConversations = rows.map(chat => ({
      ...chat,
      isCachedSnapshot: true,
      hasCachedMessages: true,
      dataFetched: true,
      allMessagesLoaded: false,
      can_reply: false,
    }));
    state.conversations.listLoadingStatus = false;
  },
  restrictFrontendInboxes(state, ids) {
    const allowed = new Set(ids);
    state.conversations.allConversations =
      state.conversations.allConversations.filter(chat =>
        allowed.has(chat.inbox_id)
      );
    state.inboxes.records = state.inboxes.records.filter(inbox =>
      allowed.has(inbox.id)
    );
    if (
      !state.conversations.allConversations.some(
        chat => chat.id === state.conversations.selectedChatId
      )
    )
      state.conversations.selectedChatId = null;
  },
  discardCachedConversation(state, id) {
    state.conversations.allConversations =
      state.conversations.allConversations.filter(
        chat => chat.id !== Number(id)
      );
    if (state.conversations.selectedChatId === Number(id))
      state.conversations.selectedChatId = null;
  },
  removeOutboxMessage(state, id) {
    state.conversations.allConversations.forEach(chat => {
      chat.messages = chat.messages.filter(message => message.id !== id);
    });
  },
};

export class FrontendCache {
  constructor() {
    this.state = reactive({
      cachedCount: 0,
      validatingSession: false,
    });
    this.scope = null;
    this.snapshot = null;
    this.generation = 0;
    this.freshAt = 0;
    this.timer = null;
    this.dbPromise = null;
  }

  db() {
    if (!this.dbPromise)
      this.dbPromise = openDB(CACHE_DB, 1, {
        upgrade(db) {
          db.createObjectStore('snapshots');
        },
      }).catch(error => {
        this.dbPromise = null;
        throw error;
      });
    return this.dbPromise;
  }

  attachStore(store) {
    this.store = store;
    store.subscribe(({ type }) => {
      if (
        !this.scope ||
        ['restoreFrontendSnapshot', 'clearFrontendSnapshot'].includes(type)
      )
        return;
      if (type === 'LOGOUT') {
        this.clear();
        return;
      }
      if (
        this.scope.key !==
          cacheScope(store.state.auth.currentUser, this.scope.accountId)?.key ||
        this.scope.permissions !==
          cacheScope(store.state.auth.currentUser, this.scope.accountId)
            ?.permissions
      ) {
        this.invalidate();
        return;
      }
      if (
        !/CONVERSATION|MESSAGE|inboxes\/|agents\/|teams\/|labels\/|accounts\//.test(
          type
        )
      )
        return;
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.flush(), 1200);
    });
  }

  async hydrate(accountId) {
    const next = cacheScope(this.store?.state.auth.currentUser, accountId);
    if (
      next?.key === this.scope?.key &&
      next?.permissions === this.scope?.permissions
    )
      return;
    if (this.scope) {
      let writeTimer;
      await Promise.race([
        this.flush(),
        new Promise(resolve => {
          writeTimer = setTimeout(resolve, 500);
        }),
      ]).finally(() => clearTimeout(writeTimer));
    }
    clearTimeout(this.timer);
    this.generation += 1;
    const generation = this.generation;
    this.scope = next;
    offlineOutbox.ready = offlineOutbox.activate(this);
    this.snapshot = null;
    this.freshAt = 0;
    this.state.cachedCount = 0;
    this.store?.commit('clearFrontendSnapshot');
    if (!next) return;
    let readTimer;
    try {
      const result = await Promise.race([
        this.db().then(async db => ({
          db,
          snapshot: await db.get('snapshots', next.key),
        })),
        new Promise(resolve => {
          readTimer = setTimeout(() => resolve(null), 500);
        }),
      ]);
      if (!result) return;
      const { db, snapshot } = result;
      if (generation !== this.generation || !snapshot) return;
      if (
        snapshot.version !== 1 ||
        !Number.isFinite(snapshot.savedAt) ||
        snapshot.savedAt > Date.now() + 60000 ||
        !Array.isArray(snapshot.conversations) ||
        !['inboxes', 'agents', 'labels', 'teams'].every(key =>
          Array.isArray(snapshot[key])
        ) ||
        snapshot.conversations.some(
          chat => !Number.isInteger(chat.id) || !Array.isArray(chat.messages)
        ) ||
        snapshot.scope !== next.key ||
        snapshot.permissions !== next.permissions ||
        Date.now() - snapshot.savedAt > CACHE_TTL
      ) {
        await db.delete('snapshots', next.key);
        return;
      }
      this.snapshot = snapshot;
      this.snapshot.conversations = snapshot.conversations.filter(
        chat => Number(chat.account_id) === next.accountId
      );
      this.state.cachedCount = snapshot.conversations.length;
      this.store.commit('restoreFrontendSnapshot', snapshot);
    } catch {
      /* Cache is optional, including private mode, quota and corrupt storage. */
    } finally {
      clearTimeout(readTimer);
      offlineOutbox.restore();
    }
  }

  restoreConversations() {
    if (
      !this.snapshot ||
      this.store.state.conversations.allConversations.length
    )
      return;
    const fresh = cacheScope(
      this.store.state.auth.currentUser,
      this.scope?.accountId
    );
    if (
      fresh?.key === this.scope?.key &&
      fresh?.permissions === this.scope?.permissions
    ) {
      this.store.commit(
        'restoreCachedConversations',
        this.snapshot.conversations
      );
    }
  }

  takeResumePath(path) {
    if (!window.chatwootConfig?.isNativeApp || !window.viperNativeResumePending)
      return null;
    window.viperNativeResumePending = false;
    const id = this.snapshot?.lastConversationId;
    if (
      path !== `/app/accounts/${this.scope?.accountId}/dashboard` ||
      !this.snapshot?.conversations.some(chat => chat.id === id)
    )
      return null;
    return `/app/accounts/${this.scope.accountId}/conversations/${id}`;
  }

  async flush() {
    clearTimeout(this.timer);
    const savedAt = this.freshAt || this.snapshot?.savedAt;
    if (!this.scope || !this.store || !savedAt) return;
    const scope = this.scope;
    const generation = this.generation;
    const snapshot = buildSnapshot(this.store.state, scope, savedAt);
    if (!snapshot) return;
    try {
      const db = await this.db();
      if (generation !== this.generation) return;
      await db.put('snapshots', snapshot, scope.key);
      if (generation === this.generation) this.snapshot = snapshot;
    } catch {
      /* No retry loop or application failure for an expendable cache. */
    }
  }

  invalidate() {
    offlineOutbox.deactivate();
    const key = this.scope?.key;
    clearTimeout(this.timer);
    this.generation += 1;
    this.scope = null;
    this.snapshot = null;
    this.freshAt = 0;
    this.state.cachedCount = 0;
    this.store?.commit('clearFrontendSnapshot');
    if (key)
      this.db()
        .then(db => db.delete('snapshots', key))
        .catch(() => {});
  }

  async clear() {
    const clearedOutbox = offlineOutbox.clear().catch(() => {});
    try {
      localStorage.setItem(
        CACHE_EPOCH_KEY,
        String(Math.max(Date.now(), (Number(cacheEpoch()) || 0) + 1))
      );
    } catch {
      /* Storage can be disabled. */
    }
    this.invalidate();
    let timer;
    try {
      await Promise.race([
        Promise.all([
          this.db().then(db => db.clear('snapshots')),
          clearedOutbox,
        ]),
        new Promise(resolve => {
          timer = setTimeout(resolve, 500);
        }),
      ]);
    } catch {
      /* Optional storage. */
    } finally {
      clearTimeout(timer);
    }
  }

  async sessionValidated() {
    this.state.validatingSession = false;
    const accountId = Number(this.store?.state.route?.params?.accountId);
    if (
      accountId &&
      !cacheScope(this.store.state.auth.currentUser, accountId) &&
      window.chatwootConfig?.isNativeApp
    ) {
      await this.clear();
      window.location.reload();
      return;
    }
    if (accountId) await this.hydrate(accountId);
    queueMicrotask(() => window.reconnectService?.onReconnect());
  }

  request(config) {
    const path = new URL(
      config.url,
      window.chatwootConfig?.apiHost || window.location.origin
    ).pathname;
    if (!/\/api\/v\d+\/accounts\//.test(path)) return config;
    const accountId = Number(path.match(/\/accounts\/(\d+)/)?.[1]);
    if (this.scope && accountId !== this.scope.accountId) {
      const error = new Error('Account changed during request');
      error.code = 'ERR_CACHE_SCOPE_CHANGED';
      throw error;
    }
    config.frontendCacheScope = this.scope?.key;
    const read =
      ['get', 'head', 'options'].includes(
        (config.method || 'get').toLowerCase()
      ) || /\/conversations\/filter$/.test(path);
    const conversationId = path.match(/\/conversations\/(\d+)(?:\/|$)/)?.[1];
    const cached = this.store?.state.conversations.allConversations.some(
      chat =>
        chat.id === Number(conversationId) &&
        (chat.isCachedSnapshot || chat.hasCachedMessages)
    );
    if (
      !read &&
      (navigator.onLine === false ||
        this.state.validatingSession ||
        (cached && !config.outboxReplay))
    ) {
      const error = new Error(
        'Cached conversations are read-only until synchronized'
      );
      error.code = 'ERR_CACHE_READ_ONLY';
      throw error;
    }
    return config;
  }

  response(response) {
    const { config = {}, status } = response;
    if (
      config.frontendCacheScope &&
      config.frontendCacheScope !== this.scope?.key
    ) {
      const error = new Error('Account changed during request');
      error.code = 'ERR_CACHE_SCOPE_CHANGED';
      throw error;
    }
    if (
      status >= 200 &&
      status < 300 &&
      config.frontendCacheScope &&
      (!this.snapshot || /\/conversations(?:\/|$)/.test(config.url || ''))
    )
      this.freshAt = Date.now();
    if (
      config.frontendCacheScope &&
      /\/inboxes$/.test(config.url || '') &&
      Array.isArray(response.data?.payload)
    ) {
      const ids = response.data.payload.map(inbox => inbox.id);
      this.store.commit('restrictFrontendInboxes', ids);
      if (this.snapshot) {
        this.snapshot.conversations = this.snapshot.conversations.filter(chat =>
          ids.includes(chat.inbox_id)
        );
        this.snapshot.inboxes = this.snapshot.inboxes.filter(inbox =>
          ids.includes(inbox.id)
        );
      }
      this.flush();
    }
    return response;
  }

  denied(error) {
    const config = error.config || {};
    if (
      !this.scope ||
      config.frontendCacheScope !== this.scope.key ||
      ![401, 403, 404].includes(error.response?.status)
    )
      return;
    const id = config.url?.match(/\/conversations\/(\d+)(?:\/|$)/)?.[1];
    if (id) {
      this.store.commit('discardCachedConversation', Number(id));
      if (this.snapshot)
        this.snapshot.conversations = this.snapshot.conversations.filter(
          chat => chat.id !== Number(id)
        );
      this.flush();
    } else if (/\/conversations(?:\/filter)?$/.test(config.url || '')) {
      this.store.commit('restrictFrontendInboxes', []);
      if (this.snapshot) this.snapshot.conversations = [];
      this.flush();
    }
  }
}

export const frontendCache = new FrontendCache();
export const frontendCachePlugin = store => {
  frontendCache.attachStore(store);
  store.subscribe(({ type }) => {
    if (/CONVERSATION|MESSAGE/.test(type)) {
      // Avoid recursively restoring on the ADD_MESSAGE mutation itself.
      if (type !== 'ADD_MESSAGE') queueMicrotask(() => offlineOutbox.restore());
    }
  });
  window.addEventListener('online', () => offlineOutbox.schedule(0));
  window.addEventListener('storage', event => {
    if (event.key === CACHE_EPOCH_KEY) frontendCache.invalidate();
  });
};
