import { Browser } from '@capacitor/browser';

export const VIPERCHAT_PRIVACY_URL =
  'https://vipertec.com.br/privacy/viperchat';

const readResponseBody = async response => {
  try {
    return await response.json();
  } catch {
    return {};
  }
};

export const openViperChatPrivacyPolicy = () =>
  Browser.open({
    url: VIPERCHAT_PRIVACY_URL,
    presentationStyle: 'popover',
  });

export const openNativeSuperAdmin = async ({ installation, headers }) => {
  const response = await fetch(
    `${installation.baseUrl}/api/v1/profile/super_admin_session`,
    {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        ...headers,
      },
    }
  );
  const body = await readResponseBody(response);

  if (!response.ok || !body.url) {
    throw new Error(body.error || 'Não foi possível abrir o Super Admin.');
  }

  await Browser.open({ url: body.url, presentationStyle: 'popover' });
};
