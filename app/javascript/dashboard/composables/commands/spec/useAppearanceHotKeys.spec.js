import { useAppearanceHotKeys } from '../useAppearanceHotKeys';
import { useI18n } from 'vue-i18n';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { setColorTheme } from 'dashboard/helper/themeHelper.js';
import { useUISettings } from 'dashboard/composables/useUISettings';

vi.mock('vue-i18n');
vi.mock('shared/helpers/localStorage');
vi.mock('dashboard/helper/themeHelper.js');
vi.mock('dashboard/composables/useUISettings');

describe('useAppearanceHotKeys', () => {
  const updateUISettings = vi.fn();

  beforeEach(() => {
    useI18n.mockReturnValue({
      t: vi.fn(key => key),
    });

    window.matchMedia = vi.fn().mockReturnValue({ matches: false });
    useUISettings.mockReturnValue({
      uiSettings: { value: { brand_theme: 'viper' } },
      updateUISettings,
    });
  });

  it('should return goToAppearanceHotKeys computed property', () => {
    const { goToAppearanceHotKeys } = useAppearanceHotKeys();
    expect(goToAppearanceHotKeys.value).toBeDefined();
  });

  it('should have the correct number of appearance options', () => {
    const { goToAppearanceHotKeys } = useAppearanceHotKeys();
    expect(goToAppearanceHotKeys.value.length).toBe(4); // 1 parent + 3 theme options
  });

  it('should have the correct parent option', () => {
    const { goToAppearanceHotKeys } = useAppearanceHotKeys();
    const parentOption = goToAppearanceHotKeys.value.find(
      option => option.id === 'appearance_settings'
    );
    expect(parentOption).toBeDefined();
    expect(parentOption.children.length).toBe(3);
  });

  it('should have the correct theme options', () => {
    const { goToAppearanceHotKeys } = useAppearanceHotKeys();
    const themeOptions = goToAppearanceHotKeys.value.filter(
      option => option.parent === 'appearance_settings'
    );
    expect(themeOptions.length).toBe(3);
    expect(themeOptions.map(option => option.id)).toEqual([
      'light',
      'dark',
      'auto',
    ]);
  });

  it('should call setAppearance when a theme option is selected', () => {
    const { goToAppearanceHotKeys } = useAppearanceHotKeys();
    const lightThemeOption = goToAppearanceHotKeys.value.find(
      option => option.id === 'light'
    );

    lightThemeOption.handler();

    expect(LocalStorage.set).toHaveBeenCalledWith(
      LOCAL_STORAGE_KEYS.COLOR_SCHEME,
      'light'
    );
    expect(updateUISettings).toHaveBeenCalledWith({
      appearance_mode: 'light',
    });
    expect(setColorTheme).toHaveBeenCalledWith(false, {
      appearance_mode: 'light',
      brand_theme: 'viper',
    });
  });

  it('should handle system dark mode preference', () => {
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });

    const { goToAppearanceHotKeys } = useAppearanceHotKeys();
    const autoThemeOption = goToAppearanceHotKeys.value.find(
      option => option.id === 'auto'
    );

    autoThemeOption.handler();

    expect(LocalStorage.set).toHaveBeenCalledWith(
      LOCAL_STORAGE_KEYS.COLOR_SCHEME,
      'auto'
    );
    expect(updateUISettings).toHaveBeenCalledWith({ appearance_mode: 'auto' });
    expect(setColorTheme).toHaveBeenCalledWith(true, {
      appearance_mode: 'auto',
      brand_theme: 'viper',
    });
  });
});
