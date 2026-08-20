import { accessSync, constants } from 'node:fs';

const required = name => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
};

export const DEVELOPMENT_RELAY_TOKEN =
  'viper-push-relay-local-development-only';

const relayToken = () => {
  const configured = process.env.VIPER_PUSH_RELAY_TOKEN?.trim();
  if (configured) {
    if (configured.length < 32) {
      throw new Error(
        'VIPER_PUSH_RELAY_TOKEN must contain at least 32 characters'
      );
    }
    return configured;
  }
  if (process.env.NODE_ENV !== 'production') return DEVELOPMENT_RELAY_TOKEN;
  return required('VIPER_PUSH_RELAY_TOKEN');
};

const assertFirebaseCredentialsReadable = () => {
  const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
  if (!credentialsPath) return;

  try {
    accessSync(credentialsPath, constants.R_OK);
  } catch {
    throw new Error(
      `GOOGLE_APPLICATION_CREDENTIALS is not readable: ${credentialsPath}`
    );
  }
};

const firebaseCredentials = () => {
  const encoded = process.env.FIREBASE_SERVICE_ACCOUNT_JSON_BASE64?.trim();
  if (!encoded) {
    assertFirebaseCredentialsReadable();
    return undefined;
  }

  try {
    const credentials = JSON.parse(
      Buffer.from(encoded, 'base64').toString('utf8')
    );
    if (!credentials.client_email || !credentials.private_key) {
      throw new Error('missing service account fields');
    }
    return credentials;
  } catch {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT_JSON_BASE64 must contain valid Base64-encoded service account JSON'
    );
  }
};

export const loadConfig = () => {
  return {
    port: Number.parseInt(process.env.PORT || '3100', 10),
    firebaseProjectId: required('FIREBASE_PROJECT_ID'),
    firebaseCredentials: firebaseCredentials(),
    relayToken: relayToken(),
  };
};
