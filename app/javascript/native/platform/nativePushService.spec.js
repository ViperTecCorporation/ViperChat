import { beforeEach, describe, expect, it, vi } from 'vitest';

const { firebaseMessaging, localListeners, localNotifications, pushListeners } =
  vi.hoisted(() => {
    const pushListenerCallbacks = {};
    const localListenerCallbacks = {};

    return {
      pushListeners: pushListenerCallbacks,
      localListeners: localListenerCallbacks,
      localNotifications: {
        addListener: vi.fn(async (event, callback) => {
          localListenerCallbacks[event] = callback;
        }),
        createChannel: vi.fn(async () => {}),
        schedule: vi.fn(async () => ({ notifications: [] })),
      },
      firebaseMessaging: {
        addListener: vi.fn(async (event, callback) => {
          pushListenerCallbacks[event] = callback;
        }),
        checkPermissions: vi.fn(async () => ({ receive: 'granted' })),
        getToken: vi.fn(async () => ({ token: 'fcm-token' })),
        requestPermissions: vi.fn(async () => ({ receive: 'granted' })),
      },
    };
  });

vi.mock('@capacitor/device', () => ({
  Device: {
    getId: vi.fn(async () => ({ identifier: 'device-123' })),
    getInfo: vi.fn(async () => ({ platform: 'android', osVersion: '12' })),
  },
}));

vi.mock('@capacitor/local-notifications', () => ({
  LocalNotifications: localNotifications,
}));

vi.mock('@capacitor-firebase/messaging', () => ({
  FirebaseMessaging: firebaseMessaging,
}));

vi.mock('dashboard/api/notificationSubscription', () => ({
  default: { create: vi.fn(async () => {}) },
}));

import {
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
});
