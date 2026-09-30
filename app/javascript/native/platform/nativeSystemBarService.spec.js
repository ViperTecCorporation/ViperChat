import { Capacitor } from '@capacitor/core';
import { startNativeSystemBarSync } from './nativeSystemBarService';

const { setThemeColor } = vi.hoisted(() => ({
  setThemeColor: vi.fn().mockResolvedValue(),
}));
vi.mock('@capacitor/core', () => ({
  Capacitor: { isNativePlatform: vi.fn(), getPlatform: vi.fn() },
  registerPlugin: () => ({ setThemeColor }),
}));

describe('native system color', () => {
  beforeEach(() => {
    setThemeColor.mockResolvedValue();
  });
  it.each(['ios', 'android'])(
    'synchronizes initial and changed theme on %s',
    async platform => {
      Capacitor.isNativePlatform.mockReturnValue(true);
      Capacitor.getPlatform.mockReturnValue(platform);
      const meta = document.createElement('meta');
      meta.name = 'theme-color';
      meta.content = '#008080';
      document.head.append(meta);
      const observer = startNativeSystemBarSync();
      expect(setThemeColor).toHaveBeenCalledWith({ color: '#008080' });
      meta.content = '#123456';
      await Promise.resolve();
      expect(setThemeColor).toHaveBeenLastCalledWith({ color: '#123456' });
      observer.disconnect();
      meta.remove();
    }
  );

  it('does not call a native plugin on the web', () => {
    Capacitor.isNativePlatform.mockReturnValue(false);
    expect(startNativeSystemBarSync()).toBeNull();
    expect(setThemeColor).not.toHaveBeenCalled();
  });
});
