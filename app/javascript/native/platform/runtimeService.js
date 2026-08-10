import { Capacitor } from '@capacitor/core';

export const PLATFORM = {
  WEB: 'web',
  PWA: 'pwa',
  ANDROID: 'android',
  IOS: 'ios',
};

export const getRuntimeInfo = () => {
  if (Capacitor.isNativePlatform()) {
    return {
      native: true,
      platform: Capacitor.getPlatform(),
    };
  }

  return {
    native: false,
    platform: window.matchMedia('(display-mode: standalone)').matches
      ? PLATFORM.PWA
      : PLATFORM.WEB,
  };
};
