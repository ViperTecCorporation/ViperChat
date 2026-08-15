import { Capacitor, registerPlugin } from '@capacitor/core';

const NativeSystemBars = registerPlugin('NativeSystemBars');

const syncThemeColor = meta => {
  const color = meta.getAttribute('content');
  if (!color) return;
  NativeSystemBars.setThemeColor({ color }).catch(() => null);
};

export const startNativeSystemBarSync = () => {
  if (!Capacitor.isNativePlatform() || Capacitor.getPlatform() !== 'android') {
    return null;
  }

  const meta = document.querySelector('meta[name="theme-color"]');
  if (!meta) return null;

  syncThemeColor(meta);
  const observer = new MutationObserver(() => syncThemeColor(meta));
  observer.observe(meta, {
    attributes: true,
    attributeFilter: ['content'],
  });
  return observer;
};
