import { beforeEach, describe, expect, it, vi } from 'vitest';

const preferences = new Map();

vi.mock('@capacitor/preferences', () => ({
  Preferences: {
    get: vi.fn(async ({ key }) => ({ value: preferences.get(key) || null })),
    set: vi.fn(async ({ key, value }) => preferences.set(key, value)),
    remove: vi.fn(async ({ key }) => preferences.delete(key)),
  },
}));

import {
  configureInstallation,
  installationServiceTestUtils,
  loadActiveInstallation,
  loadInstallations,
  refreshActiveInstallation,
  removeInstallation,
  switchInstallation,
} from './installationService';

describe('installationService', () => {
  beforeEach(() => {
    preferences.clear();
    vi.restoreAllMocks();
  });

  it('normalizes the configured server URL', () => {
    expect(
      installationServiceTestUtils.normalizeServerUrl(
        ' https://chat.example.com/// '
      )
    ).toBe('https://chat.example.com');
  });

  it('rejects a server that is not ViperChat', () => {
    expect(() =>
      installationServiceTestUtils.validateDiscovery({
        product: 'website',
        apiVersion: 1,
      })
    ).toThrow('não é uma instalação ViperChat');
  });

  it('validates and persists an installation by installationId', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        json: async () => ({
          product: 'viper-chat',
          installationId: 'inst-123',
          instanceName: 'Empresa',
          apiVersion: 1,
          features: { nativeShare: true },
          limits: { maxShareFiles: 10 },
        }),
      }))
    );

    await configureInstallation('https://chat.example.com/');

    await expect(loadActiveInstallation()).resolves.toMatchObject({
      installationId: 'inst-123',
      baseUrl: 'https://chat.example.com',
      instanceName: 'Empresa',
    });
  });

  it('keeps saved installations isolated and switches by installationId', async () => {
    const discoveries = {
      'https://one.example.com/.well-known/viper-chat': {
        product: 'viper-chat',
        installationId: 'inst-one',
        instanceName: 'One',
        apiVersion: 1,
      },
      'https://two.example.com/.well-known/viper-chat': {
        product: 'viper-chat',
        installationId: 'inst-two',
        instanceName: 'Two',
        apiVersion: 1,
      },
    };
    vi.stubGlobal(
      'fetch',
      vi.fn(async url => ({
        ok: true,
        json: async () => discoveries[url],
      }))
    );

    await configureInstallation('https://one.example.com');
    await configureInstallation('https://two.example.com');

    await expect(loadInstallations()).resolves.toHaveLength(2);
    await expect(switchInstallation('inst-one')).resolves.toMatchObject({
      instanceName: 'One',
    });
    await expect(loadActiveInstallation()).resolves.toMatchObject({
      installationId: 'inst-one',
    });

    await removeInstallation('inst-one');
    await expect(loadActiveInstallation()).resolves.toBeNull();
    await expect(loadInstallations()).resolves.toEqual([
      expect.objectContaining({ installationId: 'inst-two' }),
    ]);
  });

  it('refreshes native capabilities when the saved server configuration changes', async () => {
    let nativePush = false;
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        json: async () => ({
          product: 'viper-chat',
          installationId: 'inst-123',
          instanceName: 'ViperChat',
          version: '4.16.12-viper',
          apiVersion: 1,
          features: { nativePush },
          config: { selectedLocale: 'pt_BR' },
        }),
      }))
    );

    await configureInstallation('https://chat.example.com');
    nativePush = true;

    await expect(refreshActiveInstallation()).resolves.toMatchObject({
      features: { nativePush: true },
      config: { selectedLocale: 'pt_BR' },
    });
  });
});
