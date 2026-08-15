import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildFirebaseMessage } from '../src/firebase.js';

const payload = conversationId => ({
  device: { push_token: 'fcm-token' },
  notification: {
    title: 'Nova mensagem',
    body: 'Cliente: Olá',
    data: { account_id: 1, primary_actor: { id: conversationId } },
  },
});

test('groups and replaces Android notifications from the same conversation', () => {
  const message = buildFirebaseMessage(payload(42));

  assert.equal(message.android.collapse_key, 'viperchat:1:42');
  assert.match(message.android.notification.tag, /^viperchat:\d+$/);
  assert.equal(message.android.notification.channel_id, 'viperchat_messages');
  assert.equal(message.apns.headers['apns-collapse-id'], 'viperchat:1:42');
});

test('uses a different notification key for another conversation', () => {
  const first = buildFirebaseMessage(payload(42));
  const second = buildFirebaseMessage(payload(43));

  assert.notEqual(
    first.android.notification.tag,
    second.android.notification.tag
  );
});

test('uses no more than 20 active Android notification slots', () => {
  const tags = new Set(
    Array.from(
      { length: 100 },
      (_, index) =>
        buildFirebaseMessage(payload(index + 1)).android.notification.tag
    )
  );

  assert.ok(tags.size <= 20);
});
