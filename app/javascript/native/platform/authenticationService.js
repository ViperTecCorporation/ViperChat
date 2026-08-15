import { SecureStorage } from './secureStorageService';

const AUTH_HEADER_NAMES = [
  'access-token',
  'token-type',
  'client',
  'expiry',
  'uid',
];
const SHARE_CONTEXT_KEY = 'viper:native:share-context';

let sessionWriteQueue = Promise.resolve();

const sessionKey = installationId => `viper:${installationId}:auth`;

const resolveAccountId = user => {
  const accountId = Number(user?.account_id || user?.accounts?.[0]?.id);
  return Number.isInteger(accountId) && accountId > 0 ? accountId : null;
};

export const syncShareContext = async ({ installation, user }) => {
  const accountId = resolveAccountId(user);
  if (!installation?.installationId || !installation?.baseUrl || !accountId) {
    return null;
  }

  const context = {
    installationId: installation.installationId,
    baseUrl: installation.baseUrl,
    accountId,
    instanceName: installation.instanceName || 'ViperChat',
  };
  await SecureStorage.set({
    key: SHARE_CONTEXT_KEY,
    value: JSON.stringify(context),
  });
  return context;
};

const readResponseBody = async response => {
  try {
    return await response.json();
  } catch {
    return {};
  }
};

const extractAuthHeaders = headers =>
  AUTH_HEADER_NAMES.reduce((result, name) => {
    const value = headers?.get ? headers.get(name) : headers?.[name];
    if (value) result[name] = value;
    return result;
  }, {});

const mergeSessionHeaders = (session, headers) => ({
  ...session,
  headers: {
    ...session.headers,
    ...extractAuthHeaders(headers),
  },
});

export const loadSession = async installationId => {
  const { value } = await SecureStorage.get({
    key: sessionKey(installationId),
  });
  if (!value) return null;

  try {
    return JSON.parse(value);
  } catch {
    await SecureStorage.remove({ key: sessionKey(installationId) });
    return null;
  }
};

export const saveSession = async (installationId, session) => {
  await SecureStorage.set({
    key: sessionKey(installationId),
    value: JSON.stringify(session),
  });
  return session;
};

export const clearSession = installationId =>
  Promise.all([
    SecureStorage.remove({ key: sessionKey(installationId) }),
    SecureStorage.remove({ key: SHARE_CONTEXT_KEY }),
  ]);

export const login = async ({ installation, email, password }) => {
  const response = await fetch(`${installation.baseUrl}/auth/sign_in`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email, password }),
  });
  const body = await readResponseBody(response);

  if (response.status === 206 && body.mfa_required) {
    return { mfaRequired: true, mfaToken: body.mfa_token };
  }

  if (!response.ok) {
    throw new Error(
      body.message || body.error || 'E-mail ou senha não conferem.'
    );
  }

  const headers = extractAuthHeaders(response.headers);
  if (!headers['access-token'] || !headers.client || !headers.uid) {
    throw new Error('O servidor não retornou uma sessão compatível.');
  }

  const session = {
    headers,
    user: body.data,
  };
  await saveSession(installation.installationId, session);
  await syncShareContext({ installation, user: session.user });
  return { mfaRequired: false };
};

export const verifyMfa = async ({
  installation,
  mfaToken,
  otpCode,
  backupCode,
}) => {
  const response = await fetch(`${installation.baseUrl}/auth/sign_in`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      mfa_token: mfaToken,
      otp_code: backupCode ? undefined : otpCode,
      backup_code: backupCode || undefined,
    }),
  });
  const body = await readResponseBody(response);
  if (!response.ok) {
    throw new Error(body.message || body.error || 'Código MFA inválido.');
  }

  const headers = extractAuthHeaders(response.headers);
  if (!headers['access-token'] || !headers.client || !headers.uid) {
    throw new Error('O servidor não retornou uma sessão compatível.');
  }
  const session = {
    headers,
    user: body.data,
  };
  await saveSession(installation.installationId, session);
  await syncShareContext({ installation, user: session.user });
};

export const validateSession = async installation => {
  const session = await loadSession(installation.installationId);
  if (!session?.headers) return null;

  const response = await fetch(`${installation.baseUrl}/auth/validate_token`, {
    headers: {
      Accept: 'application/json',
      ...session.headers,
    },
  });
  const body = await readResponseBody(response);

  if (!response.ok) {
    if (response.status === 401) {
      await clearSession(installation.installationId);
      return null;
    }
    throw new Error('Não foi possível validar a sessão neste momento.');
  }

  const refreshedSession = await saveSession(
    installation.installationId,
    mergeSessionHeaders(
      {
        ...session,
        user: body.payload?.data || session.user,
      },
      response.headers
    )
  );
  await syncShareContext({ installation, user: refreshedSession.user });
  return refreshedSession;
};

// A cold Android launch can briefly lose network connectivity while the
// activity is being created from a share intent. Keep the encrypted session in
// that transient case; only an explicit 401 from validateSession clears it.
export const restoreSession = async installation => {
  const cachedSession = await loadSession(installation.installationId);
  if (!cachedSession?.headers) return null;

  try {
    return await validateSession(installation);
  } catch {
    return cachedSession;
  }
};

export const updateSessionHeaders = async (installationId, headers) => {
  sessionWriteQueue = sessionWriteQueue
    .catch(() => null)
    .then(async () => {
      const session = await loadSession(installationId);
      if (!session) return null;
      return saveSession(installationId, mergeSessionHeaders(session, headers));
    });
  return sessionWriteQueue;
};

export const authenticationServiceTestUtils = {
  extractAuthHeaders,
  resolveAccountId,
  shareContextKey: SHARE_CONTEXT_KEY,
  sessionKey,
};
