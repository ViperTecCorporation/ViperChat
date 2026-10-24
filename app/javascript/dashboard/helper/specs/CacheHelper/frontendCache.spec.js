import 'fake-indexeddb/auto';
import { createStore } from 'vuex';
import { FrontendCache, cacheMutations } from '../../CacheHelper/frontendCache';
import {
  buildSnapshot,
  CACHE_TTL,
  MAX_CACHE_BYTES,
} from '../../CacheHelper/frontendSnapshot';

const user = (id = 7, role = 'administrator') => ({
  id,
  accounts: [{ id: 1, role, status: 'active', permissions: [] }],
});
const chat = (id = 10, accountId = 1) => ({
  id,
  account_id: accountId,
  inbox_id: 3,
  status: 'open',
  last_activity_at: 100,
  meta: {
    sender: { id: 4, name: 'SYNTHETIC Contact', pubsub_token: 'do-not-store' },
    channel: 'Channel::Whatsapp',
  },
  messages: [
    {
      id: 100,
      conversation_id: id,
      content: 'SYNTHETIC cached text',
      status: 'sent',
      source_id: 'synthetic-provider-id',
      message_type: 0,
      content_attributes: {
        secret: 'do-not-store',
        data: { recording_url: 'https://invalid.test/signed' },
      },
      attachments: [{ data_url: 'https://invalid.test/media' }],
    },
  ],
});
const makeStore = (currentUser = user()) =>
  createStore({
    state: {
      auth: { currentUser },
      route: { params: { accountId: 1 } },
      conversations: {
        allConversations: [],
        selectedChatId: null,
        attachments: {},
        attachmentsMeta: {},
      },
      inboxes: { records: [] },
      agents: { records: [] },
      labels: { records: [] },
      teams: { records: {} },
      contacts: { records: {} },
      accounts: { records: [] },
    },
    mutations: {
      ...cacheMutations,
      SET_ALL_CONVERSATION(state, rows) {
        state.conversations.allConversations = rows;
      },
      changeUser(state, nextUser) {
        state.auth.currentUser = nextUser;
      },
      serverMetadata(state) {
        state.inboxes.records = [
          {
            id: 3,
            name: 'SYNTHETIC inbox',
            provider_config: { api_key: 'do-not-store' },
            webhook_verify_token: 'do-not-store',
          },
        ];
        state.teams.records = {
          8: { id: 8, name: 'SYNTHETIC team', is_member: true },
        };
        state.accounts.records = [
          {
            id: 1,
            name: 'SYNTHETIC account',
            features: { reports: true },
            settings: { secret: 'do-not-store' },
          },
        ];
      },
    },
  });

describe('scoped frontend startup cache', () => {
  let cache;
  let store;
  beforeEach(async () => {
    window.chatwootConfig = { apiHost: 'https://dev.example.test' };
    delete window.viperNativeInstallation;
    store = makeStore();
    cache = new FrontendCache();
    cache.attachStore(store);
    await cache.clear();
    await cache.hydrate(1);
    store.commit('serverMetadata');
    store.commit('SET_ALL_CONVERSATION', [chat(), chat(11, 2)]);
    cache.freshAt = Date.now();
  });
  afterEach(async () => {
    await cache.clear();
    vi.restoreAllMocks();
    delete window.chatwootConfig;
  });

  it('restores read-only conversations, messages and front metadata without credentials, pending sends or media', async () => {
    store.state.conversations.allConversations[0].messages.push({
      id: 'pending-local',
      status: 'in_progress',
      content: 'never resend',
    });
    await cache.flush();
    const saved = await (await cache.db()).get('snapshots', cache.scope.key);
    expect(saved.conversations).toHaveLength(1);
    expect(saved.conversations[0].messages).toHaveLength(1);
    expect(saved.conversations[0].messages[0].attachments).toEqual([]);
    expect(saved.conversations[0].messages[0].source_id).toBe(
      'synthetic-provider-id'
    );
    expect(JSON.stringify(saved)).not.toContain('do-not-store');
    expect(JSON.stringify(saved)).not.toContain('signed');
    const reopened = new FrontendCache();
    const reopenedStore = makeStore();
    reopened.attachStore(reopenedStore);
    await reopened.hydrate(1);
    expect(reopenedStore.state.conversations.allConversations[0]).toMatchObject(
      { id: 10, isCachedSnapshot: true, dataFetched: true, can_reply: false }
    );
    expect(reopenedStore.state.teams.records[8].is_member).toBe(true);
    expect(
      reopenedStore.state.conversations.allConversations[0].messages[0]
        .source_id
    ).toBe('synthetic-provider-id');
    expect(reopenedStore.state.contacts.records[4].name).toBe(
      'SYNTHETIC Contact'
    );
    clearTimeout(reopened.timer);
  });

  it('isolates users, installations, servers and accounts even when their numerical IDs coincide', async () => {
    await cache.flush();
    const other = new FrontendCache();
    const otherStore = makeStore(user(8));
    other.attachStore(otherStore);
    await other.hydrate(1);
    expect(otherStore.state.conversations.allConversations).toEqual([]);
    otherStore.commit('changeUser', user());
    window.viperNativeInstallation = { installationId: 'another-installation' };
    await other.hydrate(1);
    expect(otherStore.state.conversations.allConversations).toEqual([]);
    delete window.viperNativeInstallation;
    window.chatwootConfig.apiHost = 'https://other.example.test';
    await other.hydrate(1);
    expect(otherStore.state.conversations.allConversations).toEqual([]);
    expect(other.scope.key).not.toBe(cache.scope.key);
    await other.hydrate(2);
    expect(other.scope).toBeNull();
  });

  it('rejects expired and permission-incompatible snapshots without extending expiry while offline', async () => {
    cache.freshAt = Date.now() - CACHE_TTL - 1;
    await cache.flush();
    const reopened = new FrontendCache();
    const reopenedStore = makeStore();
    reopened.attachStore(reopenedStore);
    await reopened.hydrate(1);
    expect(reopenedStore.state.conversations.allConversations).toEqual([]);
    cache.freshAt = Date.now();
    await cache.flush();
    const restricted = new FrontendCache();
    const restrictedStore = makeStore(user(7, 'agent'));
    restricted.attachStore(restrictedStore);
    await restricted.hydrate(1);
    expect(restrictedStore.state.conversations.allConversations).toEqual([]);
  });

  it('blocks changes to cached conversations and all native changes until session validation, but permits reads', () => {
    store.state.conversations.allConversations[0].isCachedSnapshot = true;
    expect(() =>
      cache.request({
        method: 'post',
        url: '/api/v1/accounts/1/conversations/10/messages',
      })
    ).toThrow('read-only');
    expect(
      cache.request({
        method: 'get',
        url: '/api/v1/accounts/1/conversations/10',
      })
    ).toBeTruthy();
    store.state.conversations.allConversations[0].isCachedSnapshot = false;
    cache.state.validatingSession = true;
    expect(() =>
      cache.request({
        method: 'post',
        url: '/api/v1/accounts/1/voip/registration',
      })
    ).toThrow('read-only');
    cache.state.validatingSession = false;
    expect(
      cache.request({
        method: 'post',
        url: '/api/v1/accounts/1/conversations/10/messages',
      })
    ).toBeTruthy();
    vi.spyOn(window.navigator, 'onLine', 'get').mockReturnValue(false);
    expect(() =>
      cache.request({ method: 'post', url: '/api/v1/accounts/1/conversations' })
    ).toThrow('read-only');
  });

  it('discards late responses after account/user changes instead of contaminating the next view', async () => {
    const config = cache.request({
      method: 'get',
      url: '/api/v1/accounts/1/conversations',
    });
    store.commit('changeUser', user(8));
    await cache.hydrate(1);
    expect(() => cache.response({ status: 200, config })).toThrow(
      'Account changed'
    );
    expect(store.state.conversations.allConversations).toEqual([]);
  });

  it('removes a forbidden conversation from both memory and disk', async () => {
    await cache.flush();
    cache.denied({
      config: {
        url: '/api/v1/accounts/1/conversations/10',
        frontendCacheScope: cache.scope.key,
      },
      response: { status: 404 },
    });
    await cache.flush();
    expect(
      store.state.conversations.allConversations.some(row => row.id === 10)
    ).toBe(false);
    expect(
      (await (await cache.db()).get('snapshots', cache.scope.key)).conversations
    ).toEqual([]);
  });

  it('purges cached inboxes removed by the permission-scoped server response', async () => {
    await cache.flush();
    cache.response({
      config: {
        url: '/api/v1/accounts/1/inboxes',
        frontendCacheScope: cache.scope.key,
      },
      status: 200,
      data: { payload: [] },
    });
    await cache.flush();
    expect(store.state.conversations.allConversations).toEqual([]);
    expect(store.state.inboxes.records).toEqual([]);
    expect(
      (await (await cache.db()).get('snapshots', cache.scope.key)).conversations
    ).toEqual([]);
  });

  it('caps conversations, messages and total bytes, keeping only stable message IDs', () => {
    store.state.conversations.allConversations = Array.from(
      { length: 110 },
      (_, index) => ({
        ...chat(index),
        messages: Array.from({ length: 55 }, (__, id) => ({
          id,
          content: 'synthetic',
        })),
      })
    );
    const snapshot = buildSnapshot(store.state, cache.scope, Date.now());
    expect(snapshot.conversations).toHaveLength(100);
    expect(snapshot.conversations[0].messages).toHaveLength(50);
    expect(new Blob([JSON.stringify(snapshot)]).size).toBeLessThanOrEqual(
      MAX_CACHE_BYTES
    );
  });

  it('falls back to the normal network flow when storage is blocked, without clearing credentials', async () => {
    const blocked = new FrontendCache();
    blocked.attachStore(makeStore());
    vi.spyOn(blocked, 'db').mockRejectedValue(new Error('QuotaExceededError'));
    await expect(blocked.hydrate(1)).resolves.toBeUndefined();
    blocked.freshAt = Date.now();
    await expect(blocked.flush()).resolves.toBeUndefined();
    expect(blocked.store.state.auth.currentUser.id).toBe(7);
  });

  it('clears only its own snapshots on logout, never unrelated IndexedDB data', async () => {
    await cache.flush();
    await cache.clear();
    expect(await (await cache.db()).getAll('snapshots')).toEqual([]);
    expect(store.state.conversations.allConversations).toEqual([]);
    expect(cache.scope).toBeNull();
  });

  it('persists permission removal after cold cache hydration even without a successful network response', async () => {
    await cache.flush();
    const reopened = new FrontendCache();
    reopened.attachStore(makeStore());
    await reopened.hydrate(1);
    expect(reopened.freshAt).toBe(0);
    reopened.denied({
      config: {
        url: '/api/v1/accounts/1/conversations/10',
        frontendCacheScope: reopened.scope.key,
      },
      response: { status: 403 },
    });
    await reopened.flush();
    expect(
      (await (await reopened.db()).get('snapshots', reopened.scope.key))
        .conversations
    ).toEqual([]);
  });

  it('does not hold startup indefinitely when IndexedDB never responds', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    const blocked = new FrontendCache();
    blocked.attachStore(makeStore());
    vi.spyOn(blocked, 'db').mockReturnValue(new Promise(() => {}));
    const startup = blocked.hydrate(1);
    await vi.advanceTimersByTimeAsync(501);
    await expect(startup).resolves.toBeUndefined();
    expect(blocked.store.state.conversations.allConversations).toEqual([]);
    vi.useRealTimers();
  });

  it('resumes the last native conversation only once, never overriding an explicit deep link', async () => {
    store.state.conversations.selectedChatId = 10;
    await cache.flush();
    window.chatwootConfig.isNativeApp = true;
    window.viperNativeResumePending = true;
    expect(cache.takeResumePath('/app/accounts/1/dashboard')).toBe(
      '/app/accounts/1/conversations/10'
    );
    expect(cache.takeResumePath('/app/accounts/1/dashboard')).toBeNull();
    window.viperNativeResumePending = true;
    expect(cache.takeResumePath('/app/accounts/1/conversations/99')).toBeNull();
    delete window.viperNativeResumePending;
  });
});
