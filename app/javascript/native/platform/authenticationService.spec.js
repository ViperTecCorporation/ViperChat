import { beforeEach, describe, expect, it, vi } from 'vitest';

const secureValues = new Map();

vi.mock('./secureStorageService', () => ({
  SecureStorage: {
    get: vi.fn(async ({ key }) => ({ value: secureValues.get(key) || null })),
    set: vi.fn(async ({ key, value }) => secureValues.set(key, value)),
    remove: vi.fn(async ({ key }) => secureValues.delete(key)),
  },
}));

import {
  authenticationServiceTestUtils,
  loadSession,
  login,
  validateSession,
} from './authenticationService';

const installation = {
  installationId: 'inst-123',
  baseUrl: 'https://chat.example.com',
};

const authHeaders = {
  'access-token': 'token-123',
  'token-type': 'Bearer',
  client: 'client-123',
  expiry: '2000000000',
  uid: 'agent@example.com',
};

const responseHeaders = values => new Headers(values);

describe('authenticationService', () => {
  beforeEach(() => {
    secureValues.clear();
    vi.unstubAllGlobals();
  });

  it('stores only the session headers returned by a successful login', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        headers: responseHeaders({ ...authHeaders, 'x-request-id': 'ignored' }),
        json: async () => ({ data: { id: 7, email: 'agent@example.com' } }),
      }))
    );

    await login({
      installation,
      email: 'agent@example.com',
      password: 'secret',
    });

    await expect(loadSession('inst-123')).resolves.toEqual({
      headers: authHeaders,
      user: { id: 7, email: 'agent@example.com' },
    });
    expect(fetch).toHaveBeenCalledWith(
      'https://chat.example.com/auth/sign_in',
      expect.objectContaining({ method: 'POST' })
    );
  });

  it('removes an expired session after validation', async () => {
    secureValues.set(
      authenticationServiceTestUtils.sessionKey('inst-123'),
      JSON.stringify({ headers: authHeaders })
    );
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: false,
        status: 401,
        headers: responseHeaders({}),
        json: async () => ({}),
      }))
    );

    await expect(validateSession(installation)).resolves.toBeNull();
    await expect(loadSession('inst-123')).resolves.toBeNull();
  });

  it('does not persist passwords or unrelated response headers', () => {
    expect(
      authenticationServiceTestUtils.extractAuthHeaders(
        responseHeaders({ ...authHeaders, server: 'nginx' })
      )
    ).toEqual(authHeaders);
  });
});
