import 'fake-indexeddb/auto';
import { OfflineOutbox } from '../../CacheHelper/offlineOutbox';
import { cacheScope } from '../../CacheHelper/frontendSnapshot';
import {
  sortMessagesChronologically,
  findPendingMessageIndex,
} from '../../../store/modules/conversations/helpers';

describe('durable offline text outbox', () => {
  let outbox;
  let cache;
  let chat;
  let online;
  const pending = () => ({
    conversation_id: 10,
    message: 'SYNTHETIC offline text',
    created_at: 100,
    private: false,
    whatsapp_transport: 'unoapi',
  });
  beforeEach(async () => {
    online = false;
    vi.spyOn(navigator, 'onLine', 'get').mockImplementation(() => online);
    window.chatwootConfig = { apiHost: 'https://dev.test' };
    localStorage.clear();
    chat = {
      id: 10,
      inbox_id: 3,
      can_reply: true,
      offline_outbox_version: 1,
      messages: [],
    };
    const user = {
      id: 7,
      name: 'SYNTHETIC Agent',
      accounts: [{ id: 1, role: 'agent', status: 'active' }],
    };
    cache = {
      scope: cacheScope(user, 1),
      state: { validatingSession: false },
      store: {
        state: {
          auth: { currentUser: user },
          conversations: { allConversations: [chat] },
        },
        commit: vi.fn((type, message) => {
          if (type === 'removeOutboxMessage') {
            chat.messages = chat.messages.filter(row => row.id !== message);
            return;
          }
          const index = findPendingMessageIndex(chat, message);
          if (index >= 0) chat.messages[index] = message;
          else chat.messages.push(message);
        }),
      },
    };
    window.axios = {
      get: vi.fn().mockResolvedValue({
        data: { can_reply: true, offline_outbox_version: 1 },
      }),
      post: vi.fn(),
    };
    outbox = new OfflineOutbox();
    await outbox.activate(cache);
    await outbox.clear();
  });
  afterEach(async () => {
    await outbox.clear();
    vi.restoreAllMocks();
  });

  it('persists before displaying awaiting and restores the same bubble after reopening offline', async () => {
    await outbox.send(pending());
    expect(chat.messages[0].content_attributes.offline_queue.state).toBe(
      'waiting'
    );
    const id = chat.messages[0].id;
    outbox.deactivate();
    chat.messages = [];
    await outbox.activate(cache);
    expect(chat.messages.map(message => message.id)).toEqual([id]);
    expect(window.axios.post).not.toHaveBeenCalled();
  });

  it('retries a lost response with the same key and replaces the bubble with one server ID', async () => {
    await outbox.send(pending());
    online = true;
    window.axios.post
      .mockRejectedValueOnce(new Error('response lost'))
      .mockImplementation(async (url, data) => ({
        data: {
          id: 101,
          conversation_id: 10,
          content: data.content,
          echo_id: data.echo_id,
          content_attributes: { client_message_id: data.client_message_id },
          status: 'sent',
        },
      }));
    await outbox.pump();
    expect(outbox.records[0].state).toBe('waiting');
    await outbox.pump();
    expect(window.axios.post.mock.calls[0][1].client_message_id).toBe(
      window.axios.post.mock.calls[1][1].client_message_id
    );
    expect(window.axios.post.mock.calls[1][1].whatsapp_transport).toBe(
      'unoapi'
    );
    expect(chat.messages.map(message => message.id)).toEqual([101]);
    expect(await (await outbox.db()).getAll('messages')).toEqual([]);
  });

  it('serializes replay and preserves FIFO while the network is unavailable', async () => {
    await outbox.send(pending());
    await outbox.send({ ...pending(), message: 'second' });
    online = true;
    window.axios.post.mockRejectedValue(new Error('offline'));
    await Promise.all([outbox.pump(), outbox.pump(), outbox.pump()]);
    expect(window.axios.post).toHaveBeenCalledTimes(1);
    expect(window.axios.post.mock.calls[0][1].content).toBe(
      'SYNTHETIC offline text'
    );
  });

  it('stops on permission denial without sending or dropping the queued text', async () => {
    await outbox.send(pending());
    online = true;
    window.axios.get.mockRejectedValue({ response: { status: 403 } });
    await outbox.pump();
    expect(window.axios.post).not.toHaveBeenCalled();
    expect(outbox.records[0].state).toBe('rejected');
    expect(outbox.records[0].message.message).toBe('SYNTHETIC offline text');
    await outbox.pump();
    expect(window.axios.get).toHaveBeenCalledTimes(1);
  });

  it('does not send from a different user/account/permission scope or before native validation', async () => {
    await outbox.send(pending());
    online = true;
    cache.state.validatingSession = true;
    await outbox.pump();
    cache.state.validatingSession = false;
    cache.store.state.auth.currentUser.accounts[0].role = 'administrator';
    await outbox.pump();
    expect(window.axios.post).not.toHaveBeenCalled();
  });

  it('rejects full/failed storage without displaying a falsely queued message', async () => {
    vi.spyOn(outbox, 'db').mockRejectedValue(new Error('quota'));
    await expect(outbox.send(pending())).rejects.toThrow('quota');
    expect(chat.messages).toEqual([]);
    outbox.db.mockRestore();
  });

  it('expires instead of sending old text and supports cancellation and logout cleanup', async () => {
    await outbox.send(pending());
    outbox.records[0].createdAt = Date.now() - 25 * 3600000;
    online = true;
    await outbox.pump();
    expect(outbox.records[0].state).toBe('expired');
    expect(window.axios.post).not.toHaveBeenCalled();
    await outbox.cancel(outbox.records[0].id);
    expect(chat.messages).toEqual([]);
    expect(await (await outbox.db()).getAll('messages')).toEqual([]);
  });

  it('does not replay media, templates, interactive messages or email routing', () => {
    expect(outbox.supports(pending())).toBe(true);
    [
      { files: ['signed'] },
      { templateParams: {} },
      { contentAttributes: { whatsapp_interactive: {} } },
      { toEmails: 'test@example.test' },
    ].forEach(extra =>
      expect(outbox.supports({ ...pending(), ...extra })).toBe(false)
    );
  });

  it('keeps the legacy online path when the server has not advertised durable idempotency', () => {
    delete chat.offline_outbox_version;
    expect(outbox.supports(pending())).toBe(false);
    expect(outbox.canQueue(chat)).toBe(false);
  });

  it('never replays into an older server that ignores the client key', async () => {
    await outbox.send(pending());
    online = true;
    window.axios.get.mockResolvedValue({ data: { can_reply: true } });
    await outbox.pump();
    expect(outbox.records[0].state).toBe('rejected');
    expect(window.axios.post).not.toHaveBeenCalled();
  });

  it('deduplicates overlapping history when the server accepted a queued message without its echo', () => {
    const id = crypto.randomUUID();
    const rows = sortMessagesChronologically([
      { id: `outbox-${id}`, created_at: 100 },
      {
        id: 101,
        created_at: 101,
        content_attributes: { client_message_id: id },
      },
    ]);
    expect(rows.map(message => message.id)).toEqual([101]);
  });
});
