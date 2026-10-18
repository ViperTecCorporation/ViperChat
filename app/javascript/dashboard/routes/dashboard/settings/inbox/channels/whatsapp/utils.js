import { loadScript } from 'dashboard/helper/DOMHelpers';

export const loadFacebookSdk = async () => {
  return loadScript('https://connect.facebook.net/en_US/sdk.js', {
    async: true,
    defer: true,
    crossOrigin: 'anonymous',
  });
};

export const initializeFacebook = (appId, apiVersion) => {
  const version =
    typeof apiVersion === 'string' && /^v[1-9]\d*\.0$/.test(apiVersion)
      ? apiVersion
      : 'v26.0';
  return new Promise(resolve => {
    const init = () => {
      window.FB.init({
        appId,
        autoLogAppEvents: true,
        xfbml: true,
        version,
      });
      resolve();
    };

    if (window.FB) {
      init();
    } else {
      const previousInit = window.fbAsyncInit;
      window.fbAsyncInit = () => {
        previousInit?.();
        init();
      };
    }
  });
};

export const isValidBusinessData = businessData => {
  return Boolean(businessData && businessData.waba_id);
};

export const createMessageHandler = onEmbeddedSignupData => {
  return event => {
    if (!/^https:\/\/([a-z0-9-]+\.)*facebook\.com$/i.test(event.origin)) return;

    try {
      let data;
      if (typeof event.data === 'string') {
        data = JSON.parse(event.data);
      } else if (typeof event.data === 'object' && event.data !== null) {
        data = event.data;
      } else {
        return;
      }

      if (data.type === 'WA_EMBEDDED_SIGNUP') {
        onEmbeddedSignupData(data);
      }
    } catch {
      // Ignore non-JSON or irrelevant messages
    }
  };
};

export const initWhatsAppEmbeddedSignup = configId => {
  return new Promise((resolve, reject) => {
    window.FB.login(
      response => {
        if (response.authResponse && response.authResponse.code) {
          resolve(response.authResponse.code);
        } else if (response.error) {
          reject(new Error(response.error));
        } else {
          reject(new Error('Login cancelled'));
        }
      },
      {
        config_id: configId,
        response_type: 'code',
        override_default_response_type: true,
        extras: {
          setup: {},
          featureType: 'whatsapp_business_app_onboarding',
          sessionInfoVersion: '3',
        },
      }
    );
  });
};

export const setupFacebookSdk = async (appId, apiVersion) => {
  await loadFacebookSdk();
  await initializeFacebook(appId, apiVersion);
};
