import Auth from '../api/auth';

const parseErrorCode = error => Promise.reject(error);

const authHeaders = () => {
  const {
    'access-token': accessToken,
    'token-type': tokenType,
    client,
    expiry,
    uid,
  } = Auth.getAuthData() || {};

  return accessToken
    ? {
        'access-token': accessToken,
        'token-type': tokenType,
        client,
        expiry,
        uid,
      }
    : {};
};

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });
  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    Object.assign(wootApi.defaults.headers.common, authHeaders());
  }
  wootApi.interceptors.request.use(config => {
    if (window.chatwootConfig?.isNativeApp) {
      Object.assign(config.headers, authHeaders());
    }
    return config;
  });
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => {
      if (window.viperNativeAuth) {
        window.viperNativeAuth.updateHeaders(response.headers);
      }
      return response;
    },
    error => parseErrorCode(error)
  );
  return wootApi;
};
