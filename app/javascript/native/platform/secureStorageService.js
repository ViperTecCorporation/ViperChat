import { registerPlugin, WebPlugin } from '@capacitor/core';

class SecureStorageWeb extends WebPlugin {
  // eslint-disable-next-line class-methods-use-this
  async set({ key, value }) {
    window.sessionStorage.setItem(key, value);
  }

  // eslint-disable-next-line class-methods-use-this
  async get({ key }) {
    return { value: window.sessionStorage.getItem(key) };
  }

  // eslint-disable-next-line class-methods-use-this
  async remove({ key }) {
    window.sessionStorage.removeItem(key);
  }
}

export const SecureStorage = registerPlugin('SecureStorage', {
  web: () => Promise.resolve(new SecureStorageWeb()),
});
