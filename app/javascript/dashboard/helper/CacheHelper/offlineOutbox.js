/* eslint-disable no-await-in-loop, no-restricted-syntax, no-continue -- Replay must remain serial (FIFO), including persisted failure transitions. */
import { openDB } from 'idb';
import { cacheScope } from './frontendSnapshot';
import types from '../../store/mutation-types';

export const OUTBOX_DB = 'viper-offline-outbox-v1';
const MAX_AGE = 24 * 60 * 60 * 1000;
const retryable = error =>
  !error.response ||
  error.response.status >= 500 ||
  [408, 429].includes(error.response.status);

export class OfflineOutbox {
  constructor() {
    this.records = [];
    this.running = false;
    this.timer = null;
    this.generation = 0;
  }

  db() {
    this.database ||= openDB(OUTBOX_DB, 1, {
      upgrade(db) {
        db.createObjectStore('messages', { keyPath: 'key' });
      },
    }).catch(error => {
      this.database = null;
      throw error;
    });
    return this.database;
  }

  supports(message) {
    const attributes =
      message.contentAttributes || message.content_attributes || {};
    return Boolean(
      this.canQueue(
        this.cache?.store.state.conversations.allConversations.find(
          chat => chat.id === message.conversation_id
        )
      ) &&
        message.message?.trim() &&
        !(
          message.files?.length ||
          message.file ||
          message.attachments?.length ||
          message.templateParams ||
          message.ccEmails ||
          message.bccEmails ||
          message.toEmails
        ) &&
        (!message.contentType || message.contentType === 'text') &&
        (!message.content_type || message.content_type === 'text') &&
        Object.keys(attributes).every(key => key === 'in_reply_to')
    );
  }

  canQueue(chat) {
    return Boolean(this.cache?.scope && chat?.offline_outbox_version === 1);
  }

  waiting(chat) {
    return (
      navigator.onLine === false ||
      this.cache?.state.validatingSession ||
      Boolean(chat?.isCachedSnapshot || chat?.hasCachedMessages)
    );
  }

  async activate(cache) {
    this.cache = cache;
    this.generation += 1;
    const generation = this.generation;
    clearTimeout(this.timer);
    this.records = [];
    const scope = cache.scope;
    if (!scope) return;
    try {
      const records = await (await this.db()).getAll('messages');
      if (generation !== this.generation) return;
      this.records = records.filter(
        record =>
          record.scope === scope.key && record.permissions === scope.permissions
      );
      this.restore();
      this.schedule(0);
    } catch {
      /* Storage errors never turn a message into an untracked send. */
    }
  }

  restore() {
    if (!this.cache?.scope) return;
    for (const record of this.records) {
      const chat = this.chat(record);
      if (!chat) continue;
      const accepted = chat.messages.some(
        message =>
          Number.isInteger(message.id) &&
          message.content_attributes?.client_message_id === record.id
      );
      if (accepted) continue;
      this.cache.store.commit(types.ADD_MESSAGE, {
        ...record.message,
        sender: {
          ...record.message.sender,
          thumbnail: this.cache.store.state.auth.currentUser.avatar_url,
        },
        status: 'progress',
        content_attributes: {
          ...record.message.content_attributes,
          offline_queue: { state: record.state, id: record.id },
        },
      });
    }
  }

  chat(record) {
    return this.cache.store.state.conversations.allConversations.find(
      chat => chat.id === record.message.conversation_id
    );
  }

  schedule(delay = 1000) {
    clearTimeout(this.timer);
    if (!this.records.some(record => record.state === 'waiting')) return;
    this.timer = setTimeout(() => this.pump(), delay);
  }

  async send(pending) {
    const scope = this.cache.scope;
    await this.ready;
    if (scope.key !== this.cache.scope?.key)
      throw new Error('OUTBOX_SCOPE_CHANGED');
    const id = crypto.randomUUID();
    const attributes =
      pending.contentAttributes || pending.content_attributes || {};
    const sender = this.cache.store.state.auth.currentUser;
    const createdAt = Math.max(
      Date.now(),
      ...this.records.map(row => row.createdAt + 1)
    );
    const record = {
      key: `${scope.key}:${id}`,
      id,
      scope: scope.key,
      permissions: scope.permissions,
      createdAt,
      state: 'waiting',
      attempts: 0,
      message: {
        id: `outbox-${id}`,
        echo_id: `outbox-${id}`,
        client_message_id: id,
        conversation_id: pending.conversation_id,
        conversationId: pending.conversation_id,
        inbox_id: this.chat({ message: pending })?.inbox_id,
        account_id: scope.accountId,
        content: pending.message,
        message: pending.message,
        private: Boolean(pending.private),
        message_type: 1,
        content_type: 'text',
        content_attributes: { ...attributes },
        created_at: createdAt / 1000,
        delivery_destination: pending.delivery_destination || 'channel',
        whatsapp_transport: pending.whatsapp_transport,
        sender: {
          id: sender.id,
          name: sender.name,
          type: 'user',
        },
        attachments: [],
      },
    };
    // Persist BEFORE clearing the composer or showing a successfully queued bubble.
    const db = await this.db();
    if (
      this.records.length >= 100 ||
      JSON.stringify([...this.records, record]).length > 1024 * 1024
    )
      throw new Error('OUTBOX_FULL');
    if (scope.key !== this.cache.scope?.key)
      throw new Error('OUTBOX_SCOPE_CHANGED');
    await db.put('messages', record);
    if (scope.key !== this.cache.scope?.key) {
      await db.delete('messages', record.key);
      throw new Error('OUTBOX_SCOPE_CHANGED');
    }
    this.records.push(record);
    this.restore();
    this.schedule(0);
    return { ...record.message, queued: true };
  }

  async cancel(id) {
    const record = this.records.find(row => row.id === id);
    if (!record || record.state === 'sending') return;
    await (await this.db()).delete('messages', record.key);
    this.records = this.records.filter(row => row !== record);
    this.cache.store.commit('removeOutboxMessage', record.message.id);
  }

  async pump() {
    if (this.running || !this.cache?.scope || navigator.onLine === false)
      return;
    this.running = true;
    const scope = this.cache.scope;
    try {
      // Cross-tab exclusivity is optional; durable server idempotency is mandatory.
      for (const record of [...this.records].sort(
        (a, b) => a.createdAt - b.createdAt
      )) {
        if (record.state !== 'waiting') continue;
        const currentScope = cacheScope(
          this.cache.store.state.auth.currentUser,
          scope.accountId
        );
        if (
          scope.key !== this.cache.scope?.key ||
          currentScope?.key !== scope.key ||
          currentScope?.permissions !== record.permissions
        )
          break;
        if (Date.now() - record.createdAt > MAX_AGE) {
          record.state = 'expired';
          await (await this.db()).put('messages', record);
          continue;
        }
        if (this.cache.state.validatingSession) break;
        try {
          // Fresh authorization and capability check on every replay, including
          // conversations outside the currently displayed list/filter.
          const { data: chat } = await window.axios.get(
            `/api/v1/accounts/${scope.accountId}/conversations/${record.message.conversation_id}`
          );
          if (scope.key !== this.cache.scope?.key) break;
          if (this.cache.state.validatingSession) break;
          if (chat.offline_outbox_version !== 1) {
            record.state = 'rejected';
            await (await this.db()).put('messages', record);
            continue;
          }
          if (chat.inbox_id && chat.inbox_id !== record.message.inbox_id) {
            record.state = 'rejected';
            await (await this.db()).put('messages', record);
            continue;
          }
          if (
            !record.message.private &&
            !chat.can_reply &&
            record.message.delivery_destination !== 'web'
          ) {
            record.state = 'rejected';
            await (await this.db()).put('messages', record);
            continue;
          }
          record.state = 'sending';
          this.restore();
          const message = record.message;
          const { data } = await window.axios.post(
            `/api/v1/accounts/${scope.accountId}/conversations/${message.conversation_id}/messages`,
            {
              content: message.message,
              private: message.private,
              content_type: 'text',
              content_attributes: message.content_attributes,
              echo_id: message.echo_id,
              client_message_id: record.id,
              delivery_destination: message.delivery_destination,
              whatsapp_transport: message.whatsapp_transport,
            },
            { timeout: 15000, outboxReplay: true }
          );
          await (await this.db()).delete('messages', record.key);
          this.records = this.records.filter(row => row !== record);
          if (scope.key === this.cache.scope?.key) {
            this.cache.store.commit(types.ADD_MESSAGE, data);
            this.cache.store.commit(types.ADD_CONVERSATION_ATTACHMENTS, data);
          }
        } catch (error) {
          if (scope.key !== this.cache.scope?.key) break;
          record.state = retryable(error) ? 'waiting' : 'rejected';
          record.attempts += 1;
          await (await this.db()).put('messages', record);
          if (record.state === 'waiting') break; // Preserve FIFO during network loss.
        }
      }
    } catch {
      // Keep the durable waiting row if local storage becomes unavailable.
    } finally {
      this.running = false;
      this.restore();
      this.schedule(
        Math.min(
          60000,
          2000 *
            2 **
              Math.min(5, Math.max(0, ...this.records.map(row => row.attempts)))
        )
      );
    }
  }

  deactivate() {
    this.generation += 1;
    clearTimeout(this.timer);
    this.records = [];
  }

  async clear() {
    this.deactivate();
    await (await this.db()).clear('messages');
  }
}

export const offlineOutbox = new OfflineOutbox();
