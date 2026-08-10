import Auth from 'dashboard/api/auth';

export const getDirectUploadUrl = path => {
  const apiHost = window.chatwootConfig?.apiHost;
  if (!apiHost) return path;

  return new URL(path, `${apiHost}/`).toString();
};

export const setDirectUploadAuthHeaders = xhr => {
  const {
    'access-token': accessToken,
    'token-type': tokenType,
    client,
    expiry,
    uid,
  } = Auth.getAuthData() || {};

  if (!accessToken) return;

  xhr.setRequestHeader('access-token', accessToken);
  xhr.setRequestHeader('token-type', tokenType);
  xhr.setRequestHeader('client', client);
  xhr.setRequestHeader('expiry', expiry);
  xhr.setRequestHeader('uid', uid);
};
