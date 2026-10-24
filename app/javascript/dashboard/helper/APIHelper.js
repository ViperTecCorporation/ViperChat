import Auth from '../api/auth';
import { frontendCache } from './CacheHelper/frontendCache';

const parseErrorCode = error => {
  frontendCache.denied(error);
  return Promise.reject(error);
};

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
    return frontendCache.request(config);
  });
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => {
      frontendCache.response(response);
      if (window.viperNativeAuth) {
        window.viperNativeAuth.updateHeaders(response.headers);
      }
      return response;
    },
    error => parseErrorCode(error)
  );
  return wootApi;
};
