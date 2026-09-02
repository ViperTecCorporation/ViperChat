import { beforeEach, describe, expect, it, vi } from 'vitest';

const {
  appListeners,
  device,
  firebaseMessaging,
  localListeners,
  localNotifications,
  notificationSubscriptionsAPI,
  pushListeners,
} = vi.hoisted(() => {
  const appListenerCallbacks = {};
  const pushListenerCallbacks = {};
  const localListenerCallbacks = {};

  return {
    appListeners: appListenerCallbacks,
    device: {
      getId: vi.fn(async () => ({ identifier: 'device-123' })),
      getInfo: vi.fn(async () => ({ platform: 'android', osVersion: '12' })),
    },
    pushListeners: pushListenerCallbacks,
    localListeners: localListenerCallbacks,
    localNotifications: {
      addListener: vi.fn(async (event, callback) => {
        localListenerCallbacks[event] = callback;
      }),
      checkPermissions: vi.fn(async () => ({ display: 'granted' })),
      createChannel: vi.fn(async () => {}),
      listChannels: vi.fn(async () => ({
        channels: [{ id: 'viperchat_messages', importance: 4 }],
      })),
      removeAllDeliveredNotifications: vi.fn(async () => {}),
      schedule: vi.fn(async () => ({ notifications: [] })),
    },
    notificationSubscriptionsAPI: {
      create: vi.fn(async () => {}),
      destroy: vi.fn(async () => {}),
    },
    firebaseMessaging: {
      addListener: vi.fn(async (event, callback) => {
        pushListenerCallbacks[event] = callback;
      }),
      checkPermissions: vi.fn(async () => ({ receive: 'granted' })),
      deleteToken: vi.fn(async () => {}),
      getToken: vi.fn(async () => ({ token: 'fcm-token' })),
      requestPermissions: vi.fn(async () => ({ receive: 'granted' })),
    },
  };
});

vi.mock('@capacitor/app', () => ({
  App: {
    addListener: vi.fn(async (event, callback) => {
      appListeners[event] = callback;
    }),
  },
}));

vi.mock('@capacitor/device', () => ({
  Device: device,
}));

vi.mock('@capacitor/local-notifications', () => ({
  LocalNotifications: localNotifications,
}));

vi.mock('@capacitor-firebase/messaging', () => ({
  FirebaseMessaging: firebaseMessaging,
}));

vi.mock('dashboard/api/notificationSubscription', () => ({
  default: notificationSubscriptionsAPI,
}));

import {
  disableNativePush,
  enableNativePush,
  initializeNativePush,
  nativePushServiceTestUtils,
} from './nativePushService';

describe('nativePushService', () => {
  const router = {
    currentRoute: { value: { params: { accountId: 1 } } },
    push: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
    nativePushServiceTestUtils.reset();
    firebaseMessaging.getToken.mockResolvedValue({ token: 'fcm-token' });
    device.getInfo.mockResolvedValue({ platform: 'android', osVersion: '12' });
    localNotifications.checkPermissions.mockResolvedValue({
      display: 'granted',
    });
    localNotifications.listChannels.mockResolvedValue({
      channels: [{ id: 'viperchat_messages', importance: 4 }],
    });
  });

  it('keeps the granted permission when the platform cannot issue a token', async () => {
    firebaseMessaging.getToken.mockRejectedValueOnce(
      new Error('APNs token is not available')
    );

    const result = await enableNativePush({
      installation: {
        installationId: 'installation-123',
        features: { nativePush: true },
      },
      router,
    });

    expect(result).toEqual({ receive: 'granted', registered: false });
  });

  it('removes the server subscription and local token before logout', async () => {
    await disableNativePush();

    expect(notificationSubscriptionsAPI.destroy).toHaveBeenCalledWith(
      'fcm-token'
    );
    expect(firebaseMessaging.deleteToken).toHaveBeenCalledOnce();
    expect(
      localNotifications.removeAllDeliveredNotifications
    ).toHaveBeenCalledOnce();
  });

  it('invalidates the local token even when server cleanup fails', async () => {
    notificationSubscriptionsAPI.destroy.mockRejectedValueOnce(
      new Error('Network error')
    );

    await expect(disableNativePush()).rejects.toThrow('Network error');

    expect(firebaseMessaging.deleteToken).toHaveBeenCalledOnce();
    expect(
      localNotifications.removeAllDeliveredNotifications
    ).toHaveBeenCalledOnce();
  });

  it('shows foreground pushes and opens their conversation when tapped', async () => {
    await initializeNativePush({
      installation: {
        installationId: 'installation-123',
        features: { nativePush: true },
      },
      router,
    });

    await pushListeners.notificationReceived({
      notification: {
        title: 'Nova mensagem',
        body: 'Mensagem de teste',
        data: {
          payload: JSON.stringify({
            data: { notification: { account_id: 1, conversation_id: 42 } },
          }),
        },
      },
    });

    expect(localNotifications.createChannel).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'viperchat_messages', importance: 4 })
    );
    expect(
      localNotifications.removeAllDeliveredNotifications
    ).toHaveBeenCalledOnce();
    expect(localNotifications.schedule).toHaveBeenCalledWith({
      notifications: [
        expect.objectContaining({
          title: 'Nova mensagem',
          body: 'Mensagem de teste',
          channelId: 'viperchat_messages',
          extra: { account_id: 1, conversation_id: 42 },
        }),
      ],
    });

    localListeners.localNotificationActionPerformed({
      notification: {
        extra: { account_id: 1, conversation_id: 42 },
      },
    });

    expect(router.push).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { accountId: 1, conversation_id: 42 },
    });
  });

  it('clears delivered notifications whenever the app becomes active', async () => {
    await initializeNativePush({
      installation: {
        installationId: 'installation-123',
        features: { nativePush: true },
      },
      router,
    });

    await appListeners.appStateChange({ isActive: true });

    expect(
      localNotifications.removeAllDeliveredNotifications
    ).toHaveBeenCalledTimes(2);
  });

  it('lets iOS presentation options display foreground pushes only once', async () => {
    device.getInfo.mockResolvedValue({ platform: 'ios', osVersion: '26.0' });

    await initializeNativePush({
      installation: {
        installationId: 'installation-123',
        features: { nativePush: true },
      },
      router,
    });

    await pushListeners.notificationReceived({
      notification: {
        title: 'Nova mensagem',
        body: 'Mensagem de teste',
      },
    });

    expect(localNotifications.schedule).not.toHaveBeenCalled();
  });

  it('uses at most 20 foreground notification slots', async () => {
    await Promise.all(
      Array.from({ length: 100 }, (_, index) =>
        nativePushServiceTestUtils.showForegroundNotification({
          title: 'Nova mensagem',
          body: `Mensagem ${index}`,
          data: {
            account_id: 1,
            conversation_id: index + 1,
          },
        })
      )
    );

    const ids = localNotifications.schedule.mock.calls.map(
      ([request]) => request.notifications[0].id
    );
    expect(new Set(ids).size).toBeLessThanOrEqual(20);
  });

  it('detects app-level notification blocking on Android 7 through 12', async () => {
    localNotifications.checkPermissions.mockResolvedValueOnce({
      display: 'denied',
    });

    const result = await initializeNativePush({
      installation: {
        installationId: 'installation-123',
        features: { nativePush: true },
      },
      router,
    });

    expect(result).toEqual({ receive: 'denied', settingsTarget: 'app' });
  });

  it('detects a blocked message channel on Android 8 and newer', async () => {
    localNotifications.listChannels.mockResolvedValueOnce({
      channels: [{ id: 'viperchat_messages', importance: 0 }],
    });

    const result = await initializeNativePush({
      installation: {
        installationId: 'installation-123',
        features: { nativePush: true },
      },
      router,
    });

    expect(result).toEqual({
      receive: 'denied',
      settingsTarget: 'channel',
      channelId: 'viperchat_messages',
    });
  });
});
