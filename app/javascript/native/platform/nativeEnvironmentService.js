import { clearSession, updateSessionHeaders } from './authenticationService';
import { openNativeSuperAdmin } from './nativeBrowserService';

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

export const resolveNativeAccountId = user => {
  const accountId = Number(user?.account_id || user?.accounts?.[0]?.id);
  return Number.isInteger(accountId) && accountId > 0 ? accountId : null;
};

export const configureNativeEnvironment = ({ installation, session }) => {
  const websocketURL = installation.baseUrl.replace(/^http/, 'ws');
  const selectedLocale = installation.config?.selectedLocale || 'pt_BR';
  const accountId = resolveNativeAccountId(session.user);

  window.chatwootConfig = {
    apiHost: installation.baseUrl,
    hostURL: installation.baseUrl,
    websocketURL,
    selectedLocale,
    allowedLoginMethods: installation.config?.allowedLoginMethods || ['email'],
    signupEnabled: 'false',
    isEnterprise: 'false',
    isMfaEnabled: String(Boolean(installation.config?.mfaEnabled)),
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
    DIRECT_UPLOADS_ENABLED: Boolean(installation.config?.directUploadsEnabled),
    MAXIMUM_FILE_UPLOAD_SIZE:
      (installation.limits?.maxAttachmentBytes || 0) / 1024 / 1024,
    DEPLOYMENT_ENV: 'native',
    DISPLAY_MANIFEST: false,
    ACTIVE_PLATFORM_BANNERS: [],
  };
  window.browserConfig = { browser_name: 'ViperChat Android' };
  window.viperNativeInstallation = installation;
  window.viperNativeAccountId = accountId;
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
  window.viperNativeNavigation = {
    openSuperAdmin: () =>
      openNativeSuperAdmin({
        installation,
        headers: window.viperNativeSession,
      }),
  };

  if (accountId && !window.location.hash.includes('/app/accounts/')) {
    window.location.hash = `/app/accounts/${accountId}/dashboard`;
  }
};
