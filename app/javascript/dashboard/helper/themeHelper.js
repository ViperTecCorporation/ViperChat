import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

export const DEFAULT_THEME_SETTINGS = Object.freeze({
  appearance_mode: 'auto',
  brand_theme: 'viper',
  custom_brand_color: '#6F3935',
  custom_brand_color_dark: '#895D59',
  custom_brand_color_dark_enabled: false,
  brand_intensity: 'balanced',
  recent_brand_colors: [],
});

export const BRAND_THEME_PRESETS = Object.freeze({
  viper: { light: '#6F3935', dark: '#895D59' },
  original: { light: '#1F6FEB', dark: '#2F6FCE' },
  glow: { light: '#7C3AED', dark: '#6D28D9' },
});

const APPEARANCE_MODES = new Set(['auto', 'light', 'dark']);
const BRAND_THEMES = new Set(['viper', 'original', 'glow', 'custom']);
const BRAND_INTENSITIES = new Set(['soft', 'balanced', 'vibrant']);
const WOOT_STEPS = [25, 50, 75, 100, 200, 300, 400, 500, 600, 700, 800, 900];
const THEME_COLOR_VARIABLES = [
  '--brand-color',
  '--text-blue',
  '--text-purple',
  '--border-blue',
  '--solid-blue',
  '--solid-iris',
  '--solid-purple',
  ...Array.from({ length: 12 }, (_, index) => `--blue-${index + 1}`),
  ...Array.from({ length: 12 }, (_, index) => `--iris-${index + 1}`),
  ...Array.from({ length: 12 }, (_, index) => `--violet-${index + 1}`),
  ...WOOT_STEPS.map(step => `--woot-${step}`),
];

const clamp = value => Math.min(255, Math.max(0, Math.round(value)));

export const normalizeHexColor = color => {
  if (typeof color !== 'string') return null;
  const value = color.trim();
  if (/^#[0-9a-f]{6}$/i.test(value)) return value.toUpperCase();
  if (/^#[0-9a-f]{3}$/i.test(value)) {
    const [r, g, b] = value.slice(1).split('');
    return `#${r}${r}${g}${g}${b}${b}`.toUpperCase();
  }
  return null;
};

const hexToRgb = color => {
  const normalized =
    normalizeHexColor(color) || DEFAULT_THEME_SETTINGS.custom_brand_color;
  return {
    r: parseInt(normalized.slice(1, 3), 16),
    g: parseInt(normalized.slice(3, 5), 16),
    b: parseInt(normalized.slice(5, 7), 16),
  };
};

const rgbToHex = ({ r, g, b }) =>
  `#${[r, g, b]
    .map(channel => clamp(channel).toString(16).padStart(2, '0'))
    .join('')}`.toUpperCase();

const mix = (source, target, amount) => ({
  r: source.r + (target.r - source.r) * amount,
  g: source.g + (target.g - source.g) * amount,
  b: source.b + (target.b - source.b) * amount,
});

const adjustSaturation = (rgb, multiplier) => {
  const average = (rgb.r + rgb.g + rgb.b) / 3;
  return {
    r: average + (rgb.r - average) * multiplier,
    g: average + (rgb.g - average) * multiplier,
    b: average + (rgb.b - average) * multiplier,
  };
};

const rgbValue = rgb => `${clamp(rgb.r)} ${clamp(rgb.g)} ${clamp(rgb.b)}`;

const intensityMultiplier = intensity => {
  if (intensity === 'soft') return 0.72;
  if (intensity === 'vibrant') return 1.28;
  return 1;
};

const createPalette = (
  color,
  isDark,
  intensity,
  enhanceDarkSurfaces = false
) => {
  const base = adjustSaturation(
    hexToRgb(color),
    intensityMultiplier(intensity)
  );
  const white = { r: 255, g: 255, b: 255 };
  const black = { r: 0, g: 0, b: 0 };

  if (isDark) {
    const darkSurface = enhanceDarkSurfaces ? { r: 18, g: 18, b: 20 } : black;
    const darkMixAmounts = enhanceDarkSurfaces
      ? [0.9, 0.78, 0.64, 0.52, 0.42, 0.32, 0.22, 0.12]
      : [0.91, 0.84, 0.76, 0.67, 0.58, 0.48, 0.37, 0.24];

    return [
      ...darkMixAmounts.map(amount => mix(base, darkSurface, amount)),
      base,
      mix(base, white, 0.2),
      mix(base, white, 0.48),
      mix(base, white, 0.73),
    ];
  }

  return [
    mix(base, white, 0.98),
    mix(base, white, 0.95),
    mix(base, white, 0.9),
    mix(base, white, 0.84),
    mix(base, white, 0.75),
    mix(base, white, 0.64),
    mix(base, white, 0.5),
    mix(base, white, 0.31),
    base,
    mix(base, black, 0.1),
    mix(base, black, 0.2),
    mix(base, black, 0.31),
  ];
};

const relativeLuminance = color => {
  const rgb = hexToRgb(color);
  const channels = [rgb.r, rgb.g, rgb.b].map(channel => {
    const normalized = channel / 255;
    return normalized <= 0.03928
      ? normalized / 12.92
      : ((normalized + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
};

export const getContrastRatio = (foreground, background = '#FFFFFF') => {
  const foregroundLuminance = relativeLuminance(foreground);
  const backgroundLuminance = relativeLuminance(background);
  const lighter = Math.max(foregroundLuminance, backgroundLuminance);
  const darker = Math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
};

export const ensureAccessibleBrandColor = (color, background = '#FFFFFF') => {
  const normalized = normalizeHexColor(color);
  if (!normalized) return DEFAULT_THEME_SETTINGS.custom_brand_color;
  if (getContrastRatio(normalized, background) >= 4.5) return normalized;

  const target =
    background === '#FFFFFF'
      ? { r: 0, g: 0, b: 0 }
      : { r: 255, g: 255, b: 255 };
  const source = hexToRgb(normalized);
  for (let amount = 0.05; amount <= 0.8; amount += 0.05) {
    const candidate = rgbToHex(mix(source, target, amount));
    if (getContrastRatio(candidate, background) >= 4.5) return candidate;
  }
  return background === '#FFFFFF' ? '#000000' : '#FFFFFF';
};

export const normalizeThemeSettings = (uiSettings = {}) => {
  const cachedAppearance = LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME);
  const fallbackAppearance = APPEARANCE_MODES.has(cachedAppearance)
    ? cachedAppearance
    : DEFAULT_THEME_SETTINGS.appearance_mode;
  const appearanceMode = APPEARANCE_MODES.has(uiSettings.appearance_mode)
    ? uiSettings.appearance_mode
    : fallbackAppearance;
  const brandTheme = BRAND_THEMES.has(uiSettings.brand_theme)
    ? uiSettings.brand_theme
    : DEFAULT_THEME_SETTINGS.brand_theme;
  const brandIntensity = BRAND_INTENSITIES.has(uiSettings.brand_intensity)
    ? uiSettings.brand_intensity
    : DEFAULT_THEME_SETTINGS.brand_intensity;

  return {
    appearance_mode: appearanceMode,
    brand_theme: brandTheme,
    custom_brand_color:
      normalizeHexColor(uiSettings.custom_brand_color) ||
      DEFAULT_THEME_SETTINGS.custom_brand_color,
    custom_brand_color_dark:
      normalizeHexColor(uiSettings.custom_brand_color_dark) ||
      DEFAULT_THEME_SETTINGS.custom_brand_color_dark,
    custom_brand_color_dark_enabled:
      uiSettings.custom_brand_color_dark_enabled === true,
    brand_intensity: brandIntensity,
    recent_brand_colors: Array.isArray(uiSettings.recent_brand_colors)
      ? uiSettings.recent_brand_colors
          .map(normalizeHexColor)
          .filter(Boolean)
          .slice(0, 5)
      : [],
  };
};

export const resolveBrandColor = (settings, isDark = false) => {
  const normalized = normalizeThemeSettings(settings);
  if (normalized.brand_theme === 'custom') {
    return isDark && normalized.custom_brand_color_dark_enabled
      ? normalized.custom_brand_color_dark
      : normalized.custom_brand_color;
  }
  return BRAND_THEME_PRESETS[normalized.brand_theme][isDark ? 'dark' : 'light'];
};

export const applyBrandTheme = (settings = {}, isDark = false) => {
  const normalized = normalizeThemeSettings(settings);
  const color = resolveBrandColor(normalized, isDark);
  const palette = createPalette(
    color,
    isDark,
    normalized.brand_intensity,
    normalized.brand_theme === 'custom'
  );
  const targets = [document.documentElement, document.body].filter(Boolean);

  const setThemeProperty = (property, value) => {
    targets.forEach(target => target.style.setProperty(property, value));
  };

  palette.forEach((value, index) => {
    const rgb = rgbValue(value);
    setThemeProperty(`--blue-${index + 1}`, rgb);
    setThemeProperty(`--iris-${index + 1}`, rgb);
    setThemeProperty(`--violet-${index + 1}`, rgb);
  });

  WOOT_STEPS.forEach((step, index) => {
    setThemeProperty(`--woot-${step}`, rgbValue(palette[index]));
  });

  setThemeProperty('--brand-color', rgbValue(palette[8]));
  setThemeProperty('--text-blue', rgbValue(palette[10]));
  setThemeProperty('--text-purple', rgbValue(palette[10]));
  setThemeProperty(
    '--border-blue',
    `${rgbValue(palette[8]).replaceAll(' ', ', ')}, 0.5`
  );
  setThemeProperty('--solid-blue', rgbValue(palette[isDark ? 3 : 2]));
  setThemeProperty('--solid-iris', rgbValue(palette[isDark ? 5 : 3]));
  setThemeProperty('--solid-purple', rgbValue(palette[isDark ? 5 : 3]));

  const themeColorMeta = document.querySelector('meta[name="theme-color"]');
  themeColorMeta?.setAttribute('content', color);
};

export const clearBrandTheme = () => {
  [document.documentElement, document.body].filter(Boolean).forEach(target => {
    THEME_COLOR_VARIABLES.forEach(variable =>
      target.style.removeProperty(variable)
    );
  });
};

export const setColorTheme = (isOSOnDarkMode, settings = {}) => {
  const normalized = normalizeThemeSettings(settings);
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_SCHEME, normalized.appearance_mode);
  const isDark =
    (normalized.appearance_mode === 'auto' && isOSOnDarkMode) ||
    normalized.appearance_mode === 'dark';

  document.body.classList.toggle('dark', isDark);
  document.documentElement.classList.toggle('dark', isDark);
  document.documentElement.style.setProperty(
    'color-scheme',
    isDark ? 'dark' : 'light'
  );
  applyBrandTheme(normalized, isDark);

  return isDark;
};
