import { SecureStorage } from './secureStorageService';

const AUTH_HEADER_NAMES = [
  'access-token',
  'token-type',
  'client',
  'expiry',
  'uid',
];

let sessionWriteQueue = Promise.resolve();

const sessionKey = installationId => `viper:${installationId}:auth`;

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
  SecureStorage.remove({ key: sessionKey(installationId) });

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

  await saveSession(installation.installationId, {
    headers,
    user: body.data,
  });
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
  await saveSession(installation.installationId, {
    headers,
    user: body.data,
  });
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

  return saveSession(
    installation.installationId,
    mergeSessionHeaders(
      {
        ...session,
        user: body.payload?.data || session.user,
      },
      response.headers
    )
  );
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
  sessionKey,
};
