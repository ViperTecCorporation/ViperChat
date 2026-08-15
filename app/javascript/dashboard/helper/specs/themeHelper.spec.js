import {
  applyBrandTheme,
  ensureAccessibleBrandColor,
  getContrastRatio,
  normalizeThemeSettings,
  setColorTheme,
} from 'dashboard/helper/themeHelper.js';
import { LocalStorage } from 'shared/helpers/localStorage';

vi.mock('shared/helpers/localStorage');

describe('themeHelper', () => {
  beforeEach(() => {
    LocalStorage.get.mockReturnValue(undefined);
    document.body.classList.remove('dark');
    document.documentElement.classList.remove('dark');
    document.documentElement.removeAttribute('style');
    document.body.removeAttribute('style');
  });

  describe('setColorTheme', () => {
    it('uses the user appearance preference', () => {
      setColorTheme(true, { appearance_mode: 'light' });

      expect(document.body.classList.contains('dark')).toBe(false);
      expect(document.documentElement.style.colorScheme).toBe('light');
    });

    it('uses the operating system preference in automatic mode', () => {
      setColorTheme(true, { appearance_mode: 'auto' });

      expect(document.body.classList.contains('dark')).toBe(true);
      expect(document.documentElement.classList.contains('dark')).toBe(true);
      expect(document.documentElement.style.colorScheme).toBe('dark');
    });

    it('keeps compatibility with the cached appearance preference', () => {
      LocalStorage.get.mockReturnValue('dark');

      setColorTheme(false);

      expect(document.body.classList.contains('dark')).toBe(true);
    });

    it('updates the brand palette variables', () => {
      setColorTheme(false, {
        appearance_mode: 'light',
        brand_theme: 'glow',
      });

      expect(
        document.documentElement.style.getPropertyValue('--brand-color')
      ).toBe('124 58 237');
      expect(document.documentElement.style.getPropertyValue('--blue-9')).toBe(
        '124 58 237'
      );
    });
  });

  describe('normalizeThemeSettings', () => {
    it('uses Viper as the default brand', () => {
      expect(normalizeThemeSettings({})).toMatchObject({
        appearance_mode: 'auto',
        brand_theme: 'viper',
        brand_intensity: 'balanced',
      });
    });

    it('normalizes colors and limits recent colors', () => {
      const settings = normalizeThemeSettings({
        brand_theme: 'custom',
        custom_brand_color: '#abc',
        recent_brand_colors: [
          '#111111',
          '#222222',
          '#333333',
          '#444444',
          '#555555',
          '#666666',
          'invalid',
        ],
      });

      expect(settings.custom_brand_color).toBe('#AABBCC');
      expect(settings.recent_brand_colors).toHaveLength(5);
    });
  });

  describe('brand accessibility', () => {
    it('adjusts a color that has insufficient contrast with white', () => {
      const adjusted = ensureAccessibleBrandColor('#FFF000');

      expect(getContrastRatio(adjusted, '#FFFFFF')).toBeGreaterThanOrEqual(4.5);
    });

    it('keeps an already accessible color', () => {
      expect(ensureAccessibleBrandColor('#6F3935')).toBe('#6F3935');
    });

    it('applies a custom dark color when dark mode is active', () => {
      applyBrandTheme(
        {
          brand_theme: 'custom',
          custom_brand_color: '#112233',
          custom_brand_color_dark: '#AABBCC',
          custom_brand_color_dark_enabled: true,
        },
        true
      );

      expect(
        document.documentElement.style.getPropertyValue('--brand-color')
      ).toBe('170 187 204');
      expect(document.body.style.getPropertyValue('--brand-color')).toBe(
        '170 187 204'
      );
    });

    it('keeps custom dark surfaces visibly tinted instead of mixing them with pure black', () => {
      applyBrandTheme(
        {
          brand_theme: 'custom',
          custom_brand_color: '#00A86B',
        },
        true
      );

      expect(document.documentElement.style.getPropertyValue('--blue-3')).toBe(
        '12 72 51'
      );
      expect(document.documentElement.style.getPropertyValue('--woot-75')).toBe(
        '12 72 51'
      );
    });
  });
});
