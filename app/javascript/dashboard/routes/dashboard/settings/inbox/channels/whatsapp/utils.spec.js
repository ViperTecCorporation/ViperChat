import { loadScript } from 'dashboard/helper/DOMHelpers';
import {
  createMessageHandler,
  isValidBusinessData,
  initializeFacebook,
  initWhatsAppEmbeddedSignup,
  setupFacebookSdk,
} from './utils';

vi.mock('dashboard/helper/DOMHelpers', () => ({ loadScript: vi.fn() }));

describe('WhatsApp embedded signup business data', () => {
  it.each([
    { waba_id: 'waba-1' },
    { business_id: 'biz-1', waba_id: 'waba-1', phone_number_id: 'phone-1' },
  ])('accepts WABA data without requiring optional asset IDs: %j', data => {
    expect(isValidBusinessData(data)).toBe(true);
  });

  it.each([undefined, null, {}, { business_id: 'biz-1' }, { waba_id: '' }])(
    'rejects data without a WABA: %j',
    data => expect(isValidBusinessData(data)).toBe(false)
  );
});

describe('WhatsApp Facebook SDK', () => {
  beforeEach(() => {
    vi.stubGlobal('FB', { init: vi.fn(), login: vi.fn() });
    vi.stubGlobal('fbAsyncInit', undefined);
    loadScript.mockResolvedValue(true);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it.each([undefined, null, '', '26', 'v26', '26.0', 'invalid', {}, 26])(
    'defaults an absent or malformed version %j to Graph v26.0',
    async version => {
      await initializeFacebook('app-id', version);
      expect(window.FB.init).toHaveBeenCalledWith({
        appId: 'app-id',
        autoLogAppEvents: true,
        xfbml: true,
        version: 'v26.0',
      });
    }
  );

  it.each(['v18.0', 'v22.0', 'v25.0', 'v26.0'])(
    'honors an explicit Graph version %s, including Messenger callers',
    async version => {
      await setupFacebookSdk('app-id', version);
      expect(window.FB.init).toHaveBeenCalledWith(
        expect.objectContaining({ version })
      );
    }
  );

  it('loads the SDK with the existing script options and uses the default', async () => {
    await setupFacebookSdk('app-id');
    expect(loadScript).toHaveBeenCalledWith(
      'https://connect.facebook.net/en_US/sdk.js',
      { async: true, defer: true, crossOrigin: 'anonymous' }
    );
    expect(window.FB.init).toHaveBeenCalledWith(
      expect.objectContaining({ version: 'v26.0' })
    );
  });

  it('retains the configured version across repeated SDK setup calls', async () => {
    await setupFacebookSdk('app-id', 'v25.0');
    await setupFacebookSdk('app-id', 'v25.0');
    expect(window.FB.init).toHaveBeenCalledTimes(2);
    window.FB.init.mock.calls.forEach(([options]) => {
      expect(options.version).toBe('v25.0');
    });
  });

  it('settles every initialization waiting for the SDK without replacing a prior callback', async () => {
    const sdk = window.FB;
    window.FB = undefined;
    const previousInit = vi.fn();
    window.fbAsyncInit = previousInit;

    const first = initializeFacebook('first-app');
    const second = initializeFacebook('second-app', 'v25.0');
    window.FB = sdk;
    window.fbAsyncInit();

    await Promise.all([first, second]);
    expect(previousInit).toHaveBeenCalledOnce();
    expect(sdk.init).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ appId: 'first-app', version: 'v26.0' })
    );
    expect(sdk.init).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ appId: 'second-app', version: 'v25.0' })
    );
  });

  it('propagates a script loading failure without initializing the SDK', async () => {
    loadScript.mockRejectedValue(new Error('SDK failed'));
    await expect(setupFacebookSdk('app-id')).rejects.toThrow('SDK failed');
    expect(window.FB.init).not.toHaveBeenCalled();
  });

  it('keeps code-based popup signup and the coexistence session v3 contract', async () => {
    window.FB.login.mockImplementation(callback => {
      callback({ authResponse: { code: 'auth-code' } });
    });
    await expect(initWhatsAppEmbeddedSignup('config-id')).resolves.toBe(
      'auth-code'
    );
    expect(window.FB.login).toHaveBeenCalledWith(expect.any(Function), {
      config_id: 'config-id',
      response_type: 'code',
      override_default_response_type: true,
      extras: {
        setup: {},
        featureType: 'whatsapp_business_app_onboarding',
        sessionInfoVersion: '3',
      },
    });
  });

  it.each([
    [{}, 'Login cancelled'],
    [{ authResponse: {} }, 'Login cancelled'],
    [{ error: 'popup blocked' }, 'popup blocked'],
  ])(
    'preserves popup cancellation and errors for %j',
    async (response, error) => {
      window.FB.login.mockImplementation(callback => callback(response));
      await expect(initWhatsAppEmbeddedSignup('config-id')).rejects.toThrow(
        error
      );
    }
  );
});

describe('WhatsApp embedded signup postMessage', () => {
  it.each([
    'https://facebook.com',
    'https://www.facebook.com',
    'https://web.facebook.com',
    'https://business.facebook.com',
    'https://a.b.facebook.com',
  ])(
    'accepts Facebook origin %s for both completion events and cancel',
    origin => {
      const callback = vi.fn();
      const handler = createMessageHandler(callback);
      ['FINISH', 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING', 'CANCEL'].forEach(
        event => {
          const data = { type: 'WA_EMBEDDED_SIGNUP', event };
          handler({ origin, data });
          handler({ origin, data: JSON.stringify(data) });
          expect(callback).toHaveBeenCalledWith(data);
        }
      );
      expect(callback).toHaveBeenCalledTimes(6);
    }
  );

  it.each([
    'https://evilfacebook.com',
    'https://www.evilfacebook.com',
    'https://facebook.com.evil.com',
    'https://facebook.com@evil.com',
    'https://evil.com/facebook.com',
    'https://evil.com?facebook.com',
    'https://facebook.com:444',
    'http://facebook.com',
    'null',
    '',
  ])('ignores spoofed or untrusted origin %s', origin => {
    const callback = vi.fn();
    createMessageHandler(callback)({
      origin,
      data: { type: 'WA_EMBEDDED_SIGNUP', event: 'FINISH' },
    });
    expect(callback).not.toHaveBeenCalled();
  });

  it.each(['not JSON', null, undefined, 42, {}, { type: 'OTHER' }])(
    'ignores malformed or unrelated payload %j',
    data => {
      const callback = vi.fn();
      createMessageHandler(callback)({
        origin: 'https://www.facebook.com',
        data,
      });
      expect(callback).not.toHaveBeenCalled();
    }
  );
});
