import { FirebaseMessaging } from '@capacitor-firebase/messaging';
import { App } from '@capacitor/app';
import { Device } from '@capacitor/device';
import { LocalNotifications } from '@capacitor/local-notifications';
import NotificationSubscriptionsAPI from 'dashboard/api/notificationSubscription';

const MESSAGE_CHANNEL_ID = 'viperchat_messages';
const MAX_ANDROID_NOTIFICATION_SLOTS = 20;
const HASH_MODULUS = 2147483647;

let listenersRegistered = false;
let appStateListener;
let routerInstance;

const parseNotificationData = notification => {
  const rawPayload = notification?.data?.payload;
  if (!rawPayload) return notification?.data || {};

  try {
    const payload =
      typeof rawPayload === 'string' ? JSON.parse(rawPayload) : rawPayload;
    return payload?.data?.notification || payload?.notification || payload;
  } catch {
    return notification?.data || {};
  }
};

const openNotification = notification => {
  const data = parseNotificationData(notification);
  const conversationId = data?.primary_actor?.id || data?.conversation_id;
  const accountId = data?.account_id;
  if (!conversationId || !routerInstance) return;

  routerInstance.push({
    name: 'inbox_conversation',
    params: {
      accountId:
        accountId || routerInstance.currentRoute.value.params.accountId,
      conversation_id: conversationId,
    },
  });
};

const foregroundNotificationId = notification => {
  const data = parseNotificationData(notification);
  const key = `${data?.account_id || ''}:${data?.primary_actor?.id || data?.conversation_id || data?.primary_actor_id || ''}`;
  let hash = 0;

  for (let index = 0; index < key.length; index += 1) {
    hash = (hash * 31 + key.charCodeAt(index)) % HASH_MODULUS;
  }
  return (hash % MAX_ANDROID_NOTIFICATION_SLOTS) + 1;
};

const clearAndroidNotifications = async () => {
  const { platform } = await Device.getInfo();
  if (platform === 'android') {
    await LocalNotifications.removeAllDeliveredNotifications();
  }
};

const createMessageChannel = async () => {
  const { platform, osVersion } = await Device.getInfo();
  if (platform !== 'android' || Number.parseInt(osVersion, 10) < 8) return;

  await LocalNotifications.createChannel({
    id: MESSAGE_CHANNEL_ID,
    name: 'Mensagens',
    description: 'Novas mensagens e atualizações de conversas',
    importance: 4,
    visibility: 1,
    vibration: true,
  });
};

const showForegroundNotification = notification =>
  LocalNotifications.schedule({
    notifications: [
      {
        id: foregroundNotificationId(notification),
        title: notification.title || 'ViperChat',
        body: notification.body || '',
        largeBody: notification.body || '',
        channelId: MESSAGE_CHANNEL_ID,
        autoCancel: true,
        extra: parseNotificationData(notification),
      },
    ],
  });

const registerToken = async (installation, pushToken) => {
  if (!pushToken) return false;
  const [device, deviceInfo] = await Promise.all([
    Device.getId(),
    Device.getInfo(),
  ]);
  await NotificationSubscriptionsAPI.create({
    notification_subscription: {
      subscription_type: 'viper_native',
      subscription_attributes: {
        push_token: pushToken,
        device_id: `${installation.installationId}:${device.identifier}`,
        installation_id: installation.installationId,
        platform: deviceInfo.platform,
      },
    },
  });
  return true;
};

const registerCurrentToken = async installation => {
  try {
    const { token } = await FirebaseMessaging.getToken();
    return await registerToken(installation, token);
  } catch (error) {
    // Permission and token delivery are independent. In particular, iOS
    // simulators can grant notification permission without issuing an APNs/FCM
    // token. Keep the granted UI state and retry registration on the next app
    // activation instead of leaving the permission banner stuck on screen.
    // eslint-disable-next-line no-console
    console.error('[ViperChat] Native push token registration failed', error);
    return false;
  }
};

const registerListeners = async installation => {
  if (listenersRegistered) return;
  listenersRegistered = true;

  await createMessageChannel();

  await FirebaseMessaging.addListener('tokenReceived', event => {
    registerToken(installation, event.token).catch(error => {
      // eslint-disable-next-line no-console
      console.error('[ViperChat] Native push token update failed', error);
    });
  });
  await FirebaseMessaging.addListener('notificationActionPerformed', event =>
    openNotification(event.notification)
  );
  await FirebaseMessaging.addListener('notificationReceived', event =>
    showForegroundNotification(event.notification)
  );
  await LocalNotifications.addListener(
    'localNotificationActionPerformed',
    event => openNotification({ data: event.notification.extra })
  );
  appStateListener ||= await App.addListener('appStateChange', state => {
    clearAndroidNotifications().catch(error => {
      // eslint-disable-next-line no-console
      console.error(
        `[ViperChat] Failed to clear delivered notifications after app became ${state.isActive ? 'active' : 'inactive'}`,
        error
      );
    });
  });
};

export const getNativePushPermission = async () => {
  const [deviceInfo, firebasePermission] = await Promise.all([
    Device.getInfo(),
    FirebaseMessaging.checkPermissions(),
  ]);
  if (deviceInfo.platform !== 'android') return firebasePermission;

  const localPermission = await LocalNotifications.checkPermissions();
  if (localPermission.display === 'denied') {
    return { receive: 'denied', settingsTarget: 'app' };
  }
  if (firebasePermission.receive !== 'granted') return firebasePermission;

  if (Number.parseInt(deviceInfo.osVersion, 10) >= 8) {
    try {
      const { channels } = await LocalNotifications.listChannels();
      const messageChannel = channels.find(
        channel => channel.id === MESSAGE_CHANNEL_ID
      );
      if (Number(messageChannel?.importance) === 0) {
        return {
          receive: 'denied',
          settingsTarget: 'channel',
          channelId: MESSAGE_CHANNEL_ID,
        };
      }
    } catch {
      // Some vendor implementations do not expose channel state. In that case,
      // retain the app-level permission result instead of blocking registration.
    }
  }

  return firebasePermission;
};

export const enableNativePush = async ({ installation, router }) => {
  routerInstance = router;
  await registerListeners(installation);
  const permission = await FirebaseMessaging.requestPermissions();
  if (permission.receive !== 'granted') return permission;

  const registered = await registerCurrentToken(installation);
  return { ...permission, registered };
};

export const disableNativePush = async () => {
  let cleanupError;

  try {
    const { token } = await FirebaseMessaging.getToken();
    if (token) await NotificationSubscriptionsAPI.destroy(token);
  } catch (error) {
    cleanupError = error;
  }

  const [tokenDeletion] = await Promise.allSettled([
    FirebaseMessaging.deleteToken(),
    clearAndroidNotifications(),
  ]);

  if (cleanupError) throw cleanupError;
  if (tokenDeletion.status === 'rejected') throw tokenDeletion.reason;
};

export const initializeNativePush = async ({ installation, router }) => {
  if (!installation.features?.nativePush) return { receive: 'denied' };
  routerInstance = router;
  await registerListeners(installation);
  await clearAndroidNotifications();
  const permission = await getNativePushPermission();
  if (permission.receive === 'granted') {
    const registered = await registerCurrentToken(installation);
    return { ...permission, registered };
  }
  return permission;
};

export const nativePushServiceTestUtils = {
  parseNotificationData,
  registerCurrentToken,
  reset: () => {
    listenersRegistered = false;
    appStateListener = undefined;
    routerInstance = undefined;
  },
  showForegroundNotification,
};
