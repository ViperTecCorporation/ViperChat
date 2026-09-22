import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/settings.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/settings.json';

describe('navigation shortcut translations', () => {
  it.each([
    ['en', en],
    ['pt_BR', ptBR],
  ])('compiles the literal @ without errors in %s', (locale, messages) => {
    const errors = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      const i18n = createI18n({
        legacy: false,
        locale,
        messages: { [locale]: messages },
      });
      const description = i18n.global.t(
        'PROFILE_SETTINGS.NAVIGATION_SHORTCUTS.DESCRIPTION'
      );
      expect(description).toContain('Alt + @');
      expect(description).not.toContain("{'@'}");
      expect(errors).not.toHaveBeenCalled();
    } finally {
      errors.mockRestore();
    }
  });
});
