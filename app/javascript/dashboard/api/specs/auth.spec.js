import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { useAgentVoipStore } from 'dashboard/stores/agentVoip';

const { clearCookiesOnLogout, deleteIndexedDBOnLogout } = vi.hoisted(() => ({
  clearCookiesOnLogout: vi.fn(),
  deleteIndexedDBOnLogout: vi.fn(),
}));

vi.mock('../../store/utils/api', () => ({
  clearCookiesOnLogout,
  deleteIndexedDBOnLogout,
}));

import AuthAPI from '../auth';

describe('#AuthAPI', () => {
  const originalAxios = window.axios;
  const originalNativeAuth = window.viperNativeAuth;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    setActivePinia(undefined);
    vi.restoreAllMocks();
    window.axios = originalAxios;
    window.viperNativeAuth = originalNativeAuth;
  });

  it('stops SIP and persists teardown before invalidating the authenticated session', async () => {
    setActivePinia(createPinia());
    const calls = [];
    vi.spyOn(useAgentVoipStore(), 'stop').mockImplementation(async () =>
      calls.push('sip-stop')
    );
    window.viperNativeAuth = {
      beforeLogout: vi.fn(async () => calls.push('push-cleanup')),
    };
    window.axios = {
      delete: vi.fn(async () => {
        calls.push('sign-out');
        return { status: 200 };
      }),
    };
    await AuthAPI.logout();
    expect(calls).toEqual(['sip-stop', 'push-cleanup', 'sign-out']);
  });

  it('removes native push before ending the authenticated session', async () => {
    const calls = [];
    window.viperNativeAuth = {
      beforeLogout: vi.fn(async () => calls.push('push-cleanup')),
    };
    window.axios = {
      delete: vi.fn(async () => {
        calls.push('sign-out');
        return { status: 200 };
      }),
    };

    await AuthAPI.logout();

    expect(calls).toEqual(['push-cleanup', 'sign-out']);
    expect(deleteIndexedDBOnLogout).toHaveBeenCalledOnce();
    expect(clearCookiesOnLogout).toHaveBeenCalledOnce();
  });

  it('still signs out when native push cleanup fails', async () => {
    window.viperNativeAuth = {
      beforeLogout: vi.fn(async () => {
        throw new Error('Network error');
      }),
    };
    window.axios = {
      delete: vi.fn(async () => ({ status: 200 })),
    };

    await expect(AuthAPI.logout()).resolves.toEqual({ status: 200 });

    expect(window.axios.delete).toHaveBeenCalledOnce();
  });
});
