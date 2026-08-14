import { beforeEach, describe, expect, it, vi } from 'vitest';

const browserOpen = vi.hoisted(() => vi.fn(async () => {}));

vi.mock('@capacitor/browser', () => ({
  Browser: { open: browserOpen },
}));

import {
  openNativeSuperAdmin,
  openViperChatPrivacyPolicy,
  VIPERCHAT_PRIVACY_URL,
} from './nativeBrowserService';

describe('openViperChatPrivacyPolicy', () => {
  it('opens the public ViperChat privacy policy', async () => {
    await openViperChatPrivacyPolicy();

    expect(browserOpen).toHaveBeenCalledWith({
      url: VIPERCHAT_PRIVACY_URL,
      presentationStyle: 'popover',
    });
  });
});

describe('openNativeSuperAdmin', () => {
  const installation = { baseUrl: 'https://chat.example.com' };
  const headers = {
    'access-token': 'token',
    client: 'client',
    uid: 'admin@example.com',
  };

  beforeEach(() => {
    vi.clearAllMocks();
    global.fetch = vi.fn();
  });

  it('exchanges the API session and opens the installation URL in the native browser', async () => {
    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({
        url: 'https://chat.example.com/super_admin/native_session?token=one-time',
      }),
    });

    await openNativeSuperAdmin({ installation, headers });

    expect(global.fetch).toHaveBeenCalledWith(
      'https://chat.example.com/api/v1/profile/super_admin_session',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining(headers),
      })
    );
    expect(browserOpen).toHaveBeenCalledWith({
      url: 'https://chat.example.com/super_admin/native_session?token=one-time',
      presentationStyle: 'popover',
    });
  });

  it('does not open a browser when the session exchange is rejected', async () => {
    global.fetch.mockResolvedValue({
      ok: false,
      json: async () => ({ error: 'Super Admin access required' }),
    });

    await expect(
      openNativeSuperAdmin({ installation, headers })
    ).rejects.toThrow('Super Admin access required');
    expect(browserOpen).not.toHaveBeenCalled();
  });
});
