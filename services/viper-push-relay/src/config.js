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

export const loadConfig = () => ({
  port: Number.parseInt(process.env.PORT || '3100', 10),
  firebaseProjectId: required('FIREBASE_PROJECT_ID'),
  relayToken: relayToken(),
});
