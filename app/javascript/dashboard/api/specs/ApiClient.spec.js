import ApiClient from '../ApiClient';

describe('ApiClient native account scope', () => {
  beforeEach(() => {
    window.chatwootConfig = { isNativeApp: true };
    window.viperNativeAccountId = null;
    window.location.hash = '';
  });

  afterEach(() => {
    window.chatwootConfig = undefined;
    window.viperNativeAccountId = undefined;
    window.location.hash = '';
  });

  it('reads the account id from the native hash route', () => {
    window.location.hash = '#/app/accounts/42/dashboard';

    const client = new ApiClient('agents', { accountScoped: true });

    expect(client.url).toBe('/api/v1/accounts/42/agents');
  });

  it('uses the authenticated native account before the router is ready', () => {
    window.viperNativeAccountId = 7;

    const client = new ApiClient('contacts', { accountScoped: true });

    expect(client.url).toBe('/api/v1/accounts/7/contacts');
  });
});
