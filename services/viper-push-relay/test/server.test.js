import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { buildServer } from '../src/server.js';

const token = 'test-token-with-at-least-thirty-two-characters';
const calls = [];
const server = buildServer({
  relayToken: token,
  firebaseProjectId: 'viperchat-test',
  sendPush: async payload => {
    calls.push(payload);
    return { name: 'projects/viperchat-test/messages/123' };
  },
});
let baseUrl;

before(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
});

test('returns health without exposing credentials', async () => {
  const response = await fetch(`${baseUrl}/healthz`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: 'ok',
    firebaseProjectId: 'viperchat-test',
  });
});

test('rejects requests without the relay bearer token', async () => {
  const response = await fetch(`${baseUrl}/v1/push`, { method: 'POST' });
  assert.equal(response.status, 401);
});

test('rejects an invalid push payload', async () => {
  const response = await fetch(`${baseUrl}/v1/push`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ installation_id: 'missing-device' }),
  });
  assert.equal(response.status, 422);
});

test('validates and forwards a push payload', async () => {
  const payload = {
    installation_id: 'installation-123',
    device: {
      push_token: 'fcm-token',
      device_id: 'device-123',
      platform: 'android',
    },
    notification: {
      title: 'Nova mensagem',
      body: 'Cliente: Olá',
      data: { account_id: 1, primary_actor: { id: 42 } },
    },
  };
  const response = await fetch(`${baseUrl}/v1/push`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  assert.equal(response.status, 202);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], payload);
});
