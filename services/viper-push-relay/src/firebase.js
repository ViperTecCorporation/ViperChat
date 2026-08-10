import { GoogleAuth } from 'google-auth-library';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

const normalizeData = data => ({
  payload: JSON.stringify({ data: { notification: data || {} } }),
});

export const createFirebaseSender = ({ projectId }) => {
  const auth = new GoogleAuth({ scopes: [FCM_SCOPE] });
  const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;

  return async payload => {
    const response = await auth.request({
      url,
      method: 'POST',
      data: {
        message: {
          token: payload.device.push_token,
          notification: {
            title: payload.notification.title,
            body: payload.notification.body,
          },
          data: normalizeData(payload.notification.data),
          android: {
            priority: 'high',
            notification: { sound: 'default' },
          },
          apns: {
            payload: { aps: { sound: 'default' } },
          },
        },
      },
    });
    return response.data;
  };
};

export const firebaseErrorStatus = error => {
  const status = error?.response?.data?.error?.status;
  if (status === 'UNREGISTERED' || status === 'NOT_FOUND') return 410;
  if (status === 'RESOURCE_EXHAUSTED' || status === 'UNAVAILABLE') return 503;
  return 502;
};
