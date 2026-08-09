import { clearSession, updateSessionHeaders } from './authenticationService';

const AUTH_HEADER_NAMES = new Set([
  'access-token',
  'token-type',
  'client',
  'expiry',
  'uid',
]);

const absoluteAssetUrl = (baseUrl, value, fallback) => {
  try {
    return new URL(value || fallback, `${baseUrl}/`).toString();
  } catch {
    return new URL(fallback, `${baseUrl}/`).toString();
  }
};

export const configureNativeEnvironment = ({ installation, session }) => {
  const websocketURL = installation.baseUrl.replace(/^http/, 'ws');
  const selectedLocale = installation.config?.selectedLocale || 'pt_BR';

  window.chatwootConfig = {
    apiHost: installation.baseUrl,
    hostURL: installation.baseUrl,
    websocketURL,
    selectedLocale,
    allowedLoginMethods: installation.config?.allowedLoginMethods || ['email'],
    signupEnabled: 'false',
    isEnterprise: 'false',
    isMfaEnabled: 'false',
    inboxEventsEnabled: 'false',
    isNativeApp: true,
  };
  window.globalConfig = {
    APP_VERSION: installation.version,
    INSTALLATION_NAME: installation.instanceName,
    BRAND_NAME: installation.instanceName,
    LOGO: absoluteAssetUrl(
      installation.baseUrl,
      installation.config?.logo,
      '/brand-assets/logo.svg'
    ),
    LOGO_DARK: absoluteAssetUrl(
      installation.baseUrl,
      installation.config?.logoDark,
      '/brand-assets/logo_dark.svg'
    ),
    LOGO_THUMBNAIL: absoluteAssetUrl(
      installation.baseUrl,
      installation.config?.logoThumbnail,
      '/brand-assets/logo_thumbnail.svg'
    ),
    DIRECT_UPLOADS_ENABLED: false,
    MAXIMUM_FILE_UPLOAD_SIZE:
      (installation.limits?.maxAttachmentBytes || 0) / 1024 / 1024,
    DEPLOYMENT_ENV: 'native',
    DISPLAY_MANIFEST: false,
    ACTIVE_PLATFORM_BANNERS: [],
  };
  window.browserConfig = { browser_name: 'ViperChat Android' };
  window.errorLoggingConfig = '';
  window.viperNativeSession = session.headers;
  window.viperNativeAuth = {
    updateHeaders: headers => {
      const headerObject = Object.fromEntries(
        Object.entries(headers || {}).filter(
          ([name, value]) => AUTH_HEADER_NAMES.has(name) && Boolean(value)
        )
      );
      if (!Object.keys(headerObject).length) return Promise.resolve();
      window.viperNativeSession = {
        ...window.viperNativeSession,
        ...headerObject,
      };
      return updateSessionHeaders(installation.installationId, headerObject);
    },
    clear: () => clearSession(installation.installationId),
  };
};
