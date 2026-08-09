import { Preferences } from '@capacitor/preferences';

const ACTIVE_INSTALLATION_ID_KEY = 'viper:native:active-installation-id';
const INSTALLATIONS_KEY = 'viper:native:installations';
const SUPPORTED_API_VERSION = 1;
const DEFAULT_SERVER_URL = 'https://chatwoot.vipertec.net';

const normalizeServerUrl = value => {
  const url = new URL(value.trim());

  if (url.protocol !== 'https:' && !import.meta.env.DEV) {
    throw new Error('O servidor precisa usar HTTPS.');
  }

  url.hash = '';
  url.search = '';
  url.pathname = url.pathname.replace(/\/+$/, '');
  return url.toString().replace(/\/$/, '');
};

const validateDiscovery = discovery => {
  if (discovery?.product !== 'viper-chat') {
    throw new Error('Este endereço não é uma instalação ViperChat compatível.');
  }

  if (!discovery.installationId) {
    throw new Error('A instalação não informou um identificador válido.');
  }

  if (discovery.apiVersion !== SUPPORTED_API_VERSION) {
    throw new Error(
      'A versão da API native não é compatível com este aplicativo.'
    );
  }
};

export const getDefaultServerUrl = () => DEFAULT_SERVER_URL;

export const loadInstallations = async () => {
  const { value } = await Preferences.get({ key: INSTALLATIONS_KEY });
  if (!value) return [];

  try {
    const installations = JSON.parse(value);
    return Array.isArray(installations) ? installations : [];
  } catch {
    return [];
  }
};

export const loadActiveInstallation = async () => {
  const [{ value: activeInstallationId }, installations] = await Promise.all([
    Preferences.get({ key: ACTIVE_INSTALLATION_ID_KEY }),
    loadInstallations(),
  ]);

  return (
    installations.find(
      installation => installation.installationId === activeInstallationId
    ) || null
  );
};

export const configureInstallation = async serverUrl => {
  const baseUrl = normalizeServerUrl(serverUrl);
  const response = await fetch(`${baseUrl}/.well-known/viper-chat`, {
    headers: { Accept: 'application/json' },
  });

  if (!response.ok) {
    throw new Error('Não foi possível validar o servidor informado.');
  }

  const discovery = await response.json();
  validateDiscovery(discovery);

  const installation = {
    installationId: discovery.installationId,
    baseUrl,
    instanceName: discovery.instanceName,
    apiVersion: discovery.apiVersion,
    features: discovery.features,
    limits: discovery.limits,
  };

  const savedInstallations = await loadInstallations();
  const installations = [
    ...savedInstallations.filter(
      saved => saved.installationId !== installation.installationId
    ),
    installation,
  ];

  await Promise.all([
    Preferences.set({
      key: INSTALLATIONS_KEY,
      value: JSON.stringify(installations),
    }),
    Preferences.set({
      key: ACTIVE_INSTALLATION_ID_KEY,
      value: installation.installationId,
    }),
  ]);

  return installation;
};

export const switchInstallation = async installationId => {
  const installations = await loadInstallations();
  const installation = installations.find(
    saved => saved.installationId === installationId
  );

  if (!installation) {
    throw new Error('A instalação selecionada não está configurada.');
  }

  await Preferences.set({
    key: ACTIVE_INSTALLATION_ID_KEY,
    value: installationId,
  });

  return installation;
};

export const removeInstallation = async installationId => {
  const [activeInstallation, installations] = await Promise.all([
    loadActiveInstallation(),
    loadInstallations(),
  ]);
  const remainingInstallations = installations.filter(
    installation => installation.installationId !== installationId
  );

  await Preferences.set({
    key: INSTALLATIONS_KEY,
    value: JSON.stringify(remainingInstallations),
  });

  if (activeInstallation?.installationId === installationId) {
    await Preferences.remove({ key: ACTIVE_INSTALLATION_ID_KEY });
  }
};

export const installationServiceTestUtils = {
  normalizeServerUrl,
  validateDiscovery,
};
