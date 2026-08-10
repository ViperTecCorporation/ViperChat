import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import { DEVELOPMENT_RELAY_TOKEN, loadConfig } from '../src/config.js';

const originalEnvironment = {
  FIREBASE_PROJECT_ID: process.env.FIREBASE_PROJECT_ID,
  NODE_ENV: process.env.NODE_ENV,
  PORT: process.env.PORT,
  VIPER_PUSH_RELAY_TOKEN: process.env.VIPER_PUSH_RELAY_TOKEN,
};

afterEach(() => {
  for (const [name, value] of Object.entries(originalEnvironment)) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
});

test('uses the documented token only outside production', () => {
  process.env.NODE_ENV = 'development';
  process.env.FIREBASE_PROJECT_ID = 'viperchat-test';
  delete process.env.VIPER_PUSH_RELAY_TOKEN;

  assert.equal(loadConfig().relayToken, DEVELOPMENT_RELAY_TOKEN);
});

test('requires an explicit relay token in production', () => {
  process.env.NODE_ENV = 'production';
  process.env.FIREBASE_PROJECT_ID = 'viperchat-test';
  delete process.env.VIPER_PUSH_RELAY_TOKEN;

  assert.throws(() => loadConfig(), /VIPER_PUSH_RELAY_TOKEN is required/);
});

test('rejects short configured tokens', () => {
  process.env.NODE_ENV = 'production';
  process.env.FIREBASE_PROJECT_ID = 'viperchat-test';
  process.env.VIPER_PUSH_RELAY_TOKEN = 'too-short';

  assert.throws(() => loadConfig(), /at least 32 characters/);
});
