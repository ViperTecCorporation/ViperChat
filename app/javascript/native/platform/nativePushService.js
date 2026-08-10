import { Device } from '@capacitor/device';
import { PushNotifications } from '@capacitor/push-notifications';
import NotificationSubscriptionsAPI from 'dashboard/api/notificationSubscription';

let listenersRegistered = false;
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

const registerListeners = async installation => {
  if (listenersRegistered) return;
  listenersRegistered = true;

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

export const nativePushServiceTestUtils = { parseNotificationData };
