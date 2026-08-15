import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  ICON_APPEARANCE,
  ICON_LIGHT_MODE,
  ICON_DARK_MODE,
  ICON_SYSTEM_MODE,
} from 'dashboard/helper/commandbar/icons';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { setColorTheme } from 'dashboard/helper/themeHelper.js';
import { useUISettings } from 'dashboard/composables/useUISettings';

const getThemeOptions = t => [
  {
    key: 'light',
    label: t('COMMAND_BAR.COMMANDS.LIGHT_MODE'),
    icon: ICON_LIGHT_MODE,
  },
  {
    key: 'dark',
    label: t('COMMAND_BAR.COMMANDS.DARK_MODE'),
    icon: ICON_DARK_MODE,
  },
  {
    key: 'auto',
    label: t('COMMAND_BAR.COMMANDS.SYSTEM_MODE'),
    icon: ICON_SYSTEM_MODE,
  },
];

const setAppearance = (theme, uiSettings, updateUISettings) => {
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_SCHEME, theme);
  const nextSettings = { ...uiSettings, appearance_mode: theme };
  updateUISettings({ appearance_mode: theme });
  const isOSOnDarkMode = window.matchMedia(
    '(prefers-color-scheme: dark)'
  ).matches;
  setColorTheme(isOSOnDarkMode, nextSettings);
};

export function useAppearanceHotKeys() {
  const { t } = useI18n();
  const { uiSettings, updateUISettings } = useUISettings();

  const themeOptions = computed(() => getThemeOptions(t));

  const goToAppearanceHotKeys = computed(() => {
    const options = themeOptions.value.map(theme => ({
      id: theme.key,
      title: theme.label,
      parent: 'appearance_settings',
      section: t('COMMAND_BAR.SECTIONS.APPEARANCE'),
      icon: theme.icon,
      handler: () => {
        setAppearance(theme.key, uiSettings.value, updateUISettings);
      },
    }));
    return [
      {
        id: 'appearance_settings',
        title: t('COMMAND_BAR.COMMANDS.CHANGE_APPEARANCE'),
        section: t('COMMAND_BAR.SECTIONS.APPEARANCE'),
        icon: ICON_APPEARANCE,
        children: options.map(option => option.id),
      },
      ...options,
    ];
  });

  return {
    goToAppearanceHotKeys,
  };
}
