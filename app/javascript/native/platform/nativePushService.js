import { Device } from '@capacitor/device';
import { LocalNotifications } from '@capacitor/local-notifications';
import { PushNotifications } from '@capacitor/push-notifications';
import NotificationSubscriptionsAPI from 'dashboard/api/notificationSubscription';

const MESSAGE_CHANNEL_ID = 'viperchat_messages';
const MAX_NOTIFICATION_ID = 2147483647;

let listenersRegistered = false;
let routerInstance;
let foregroundNotificationId = Date.now() % MAX_NOTIFICATION_ID;

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

const nextForegroundNotificationId = () => {
  foregroundNotificationId =
    (foregroundNotificationId + 1) % MAX_NOTIFICATION_ID;
  return foregroundNotificationId;
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
        id: nextForegroundNotificationId(),
        title: notification.title || 'ViperChat',
        body: notification.body || '',
        largeBody: notification.body || '',
        channelId: MESSAGE_CHANNEL_ID,
        autoCancel: true,
        extra: parseNotificationData(notification),
      },
    ],
  });

const registerListeners = async installation => {
  if (listenersRegistered) return;
  listenersRegistered = true;

  await createMessageChannel();

  await PushNotifications.addListener('registration', async token => {
    const device = await Device.getId();
    await NotificationSubscriptionsAPI.create({
      notification_subscription: {
        subscription_type: 'viper_native',
        subscription_attributes: {
          push_token: token.value,
          device_id: `${installation.installationId}:${device.identifier}`,
          installation_id: installation.installationId,
          platform: 'android',
        },
      },
    });
  });

  await PushNotifications.addListener('registrationError', error => {
    // eslint-disable-next-line no-console
    console.error('[ViperChat] Native push registration failed', error);
  });
  await PushNotifications.addListener(
    'pushNotificationActionPerformed',
    event => openNotification(event.notification)
  );
  await PushNotifications.addListener(
    'pushNotificationReceived',
    showForegroundNotification
  );
  await LocalNotifications.addListener(
    'localNotificationActionPerformed',
    event => openNotification({ data: event.notification.extra })
  );
};

export const getNativePushPermission = () =>
  PushNotifications.checkPermissions();

export const enableNativePush = async ({ installation, router }) => {
  routerInstance = router;
  await registerListeners(installation);
  const permission = await PushNotifications.requestPermissions();
  if (permission.receive !== 'granted') return permission;

  await PushNotifications.register();
  return permission;
};

export const initializeNativePush = async ({ installation, router }) => {
  if (!installation.features?.nativePush) return { receive: 'denied' };
  routerInstance = router;
  await registerListeners(installation);
  const permission = await getNativePushPermission();
  if (permission.receive === 'granted') await PushNotifications.register();
  return permission;
};

export const nativePushServiceTestUtils = {
  parseNotificationData,
  showForegroundNotification,
};
