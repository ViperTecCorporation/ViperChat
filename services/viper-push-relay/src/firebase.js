import { GoogleAuth } from 'google-auth-library';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const MAX_ANDROID_NOTIFICATION_SLOTS = 20;
const HASH_MODULUS = 2147483647;

const normalizeData = data => ({
  payload: JSON.stringify({ data: { notification: data || {} } }),
});

const notificationKey = data => {
  const accountId = data?.account_id;
  const conversationId =
    data?.primary_actor?.id || data?.conversation_id || data?.primary_actor_id;

  if (!accountId || !conversationId) return 'viperchat';
  return `viperchat:${accountId}:${conversationId}`;
};

const stableHash = value => {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) % HASH_MODULUS;
  }
  return hash;
};

const androidNotificationTag = key =>
  `viperchat:${stableHash(key) % MAX_ANDROID_NOTIFICATION_SLOTS}`;

export const buildFirebaseMessage = payload => {
  const key = notificationKey(payload.notification.data);

  return {
    token: payload.device.push_token,
    notification: {
      title: payload.notification.title,
      body: payload.notification.body,
    },
    data: normalizeData(payload.notification.data),
    android: {
      collapse_key: key,
      priority: 'high',
      notification: {
        channel_id: 'viperchat_messages',
        sound: 'default',
        tag: androidNotificationTag(key),
      },
    },
    apns: {
      headers: { 'apns-collapse-id': key },
      payload: { aps: { sound: 'default', 'thread-id': key } },
    },
  };
};

export const createFirebaseSender = ({ projectId, credentials }) => {
  const auth = new GoogleAuth({ credentials, scopes: [FCM_SCOPE] });
  const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;

  return async payload => {
    const response = await auth.request({
      url,
      method: 'POST',
      data: {
        message: buildFirebaseMessage(payload),
      },
    });
    return response.data;
  };
};

export const firebaseErrorStatus = error => {
  const status = error?.response?.data?.error?.status;
  if (status === 'UNREGISTERED' || status === 'NOT_FOUND') return 410;
  if (status === 'RESOURCE_EXHAUSTED' || status === 'UNAVAILABLE') return 503;
  return undefined;
};
