<script setup>
import { computed, nextTick, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  BRAND_THEME_PRESETS,
  DEFAULT_THEME_SETTINGS,
  ensureAccessibleBrandColor,
  getContrastRatio,
  normalizeHexColor,
  normalizeThemeSettings,
  resolveBrandColor,
} from 'dashboard/helper/themeHelper';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const dialogRef = ref(null);
const isSaving = ref(false);
const showAdvanced = ref(false);
const form = reactive({ ...DEFAULT_THEME_SETTINGS });

const appearanceOptions = computed(() => [
  {
    value: 'auto',
    label: t('THEME_SETTINGS.APPEARANCE.SYSTEM'),
    icon: 'i-lucide-monitor-cog',
  },
  {
    value: 'light',
    label: t('THEME_SETTINGS.APPEARANCE.LIGHT'),
    icon: 'i-lucide-sun',
  },
  {
    value: 'dark',
    label: t('THEME_SETTINGS.APPEARANCE.DARK'),
    icon: 'i-lucide-moon',
  },
]);

const brandOptions = computed(() => [
  { value: 'viper', label: 'Viper', color: BRAND_THEME_PRESETS.viper.light },
  {
    value: 'original',
    label: t('THEME_SETTINGS.BRAND.ORIGINAL'),
    color: BRAND_THEME_PRESETS.original.light,
  },
  { value: 'glow', label: 'Glow', color: BRAND_THEME_PRESETS.glow.light },
  {
    value: 'custom',
    label: t('THEME_SETTINGS.BRAND.CUSTOM'),
    color: form.custom_brand_color,
    custom: true,
  },
]);

const intensityOptions = computed(() => [
  { value: 'soft', label: t('THEME_SETTINGS.INTENSITY.SOFT') },
  { value: 'balanced', label: t('THEME_SETTINGS.INTENSITY.BALANCED') },
  { value: 'vibrant', label: t('THEME_SETTINGS.INTENSITY.VIBRANT') },
]);

const prefersDarkMode = () =>
  window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;

const isPreviewDark = computed(
  () =>
    form.appearance_mode === 'dark' ||
    (form.appearance_mode === 'auto' && prefersDarkMode())
);

const previewColor = computed(() =>
  resolveBrandColor(form, isPreviewDark.value)
);

const previewStyle = computed(() => ({
  '--theme-preview-brand': previewColor.value,
}));

const contrastRatio = computed(() =>
  getContrastRatio(previewColor.value, '#FFFFFF')
);

const hasAccessibleContrast = computed(() => contrastRatio.value >= 4.5);

const syncForm = () => {
  Object.assign(form, normalizeThemeSettings(uiSettings.value));
  showAdvanced.value = false;
};

watch(
  () => props.show,
  async show => {
    if (!show) return;
    syncForm();
    await nextTick();
    dialogRef.value?.open();
  },
  { immediate: true }
);

const close = () => {
  dialogRef.value?.close();
};

const setCustomColor = value => {
  const color = normalizeHexColor(value);
  if (!color) return;
  form.custom_brand_color = color;
  form.brand_theme = 'custom';
};

const setCustomDarkColor = value => {
  const color = normalizeHexColor(value);
  if (color) form.custom_brand_color_dark = color;
};

const useRecentColor = color => {
  setCustomColor(color);
};

const restoreDefaults = () => {
  Object.assign(form, DEFAULT_THEME_SETTINGS);
  showAdvanced.value = false;
};

const save = async () => {
  isSaving.value = true;
  try {
    const lightColor = ensureAccessibleBrandColor(
      form.custom_brand_color,
      '#FFFFFF'
    );
    const darkColor = form.custom_brand_color_dark_enabled
      ? ensureAccessibleBrandColor(form.custom_brand_color_dark, '#FFFFFF')
      : lightColor;
    const recentColors =
      form.brand_theme === 'custom'
        ? [lightColor, ...form.recent_brand_colors]
            .filter((color, index, colors) => colors.indexOf(color) === index)
            .slice(0, 5)
        : form.recent_brand_colors;

    const result = await updateUISettings({
      appearance_mode: form.appearance_mode,
      brand_theme: form.brand_theme,
      custom_brand_color: lightColor,
      custom_brand_color_dark: darkColor,
      custom_brand_color_dark_enabled: form.custom_brand_color_dark_enabled,
      brand_intensity: form.brand_intensity,
      recent_brand_colors: recentColors,
    });
    if (result === false) throw new Error('Unable to save theme settings');
    useAlert(t('THEME_SETTINGS.MESSAGES.SAVED'));
    close();
  } catch (error) {
    useAlert(t('THEME_SETTINGS.MESSAGES.ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('THEME_SETTINGS.TITLE')"
    :description="t('THEME_SETTINGS.DESCRIPTION')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="2xl"
    mobile-constrained
    dialog-class="theme-settings-dialog"
    content-class="sm:max-h-[calc(100dvh-2rem)] sm:!overflow-y-auto"
    class="sm:max-h-[calc(100dvh-2rem)] sm:!overflow-y-auto"
    @close="emit('close')"
  >
    <div
      class="theme-settings-dialog__body -mr-2 flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto overscroll-contain pr-2"
    >
      <section class="flex flex-col gap-2.5">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('THEME_SETTINGS.APPEARANCE.LABEL') }}
        </h4>
        <div class="grid grid-cols-3 gap-2">
          <button
            v-for="option in appearanceOptions"
            :key="option.value"
            type="button"
            class="flex h-11 items-center justify-center gap-2 rounded-xl border text-sm transition-colors"
            :class="
              form.appearance_mode === option.value
                ? 'border-n-brand bg-n-brand/10 text-n-blue-11'
                : 'border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-strong hover:text-n-slate-12'
            "
            @click="form.appearance_mode = option.value"
          >
            <span class="size-4" :class="option.icon" />
            <span>{{ option.label }}</span>
          </button>
        </div>
      </section>

      <section class="flex flex-col gap-2.5">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('THEME_SETTINGS.BRAND.LABEL') }}
        </h4>
        <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <button
            v-for="option in brandOptions"
            :key="option.value"
            type="button"
            class="flex h-11 items-center justify-center gap-2 rounded-xl border text-sm transition-colors"
            :class="
              form.brand_theme === option.value
                ? 'border-n-brand bg-n-brand/10 text-n-blue-11'
                : 'border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-strong hover:text-n-slate-12'
            "
            @click="form.brand_theme = option.value"
          >
            <span
              class="size-4 rounded-full border border-n-weak"
              :class="option.custom ? 'theme-custom-swatch' : ''"
              :style="
                option.custom ? undefined : { backgroundColor: option.color }
              "
            />
            <span>{{ option.label }}</span>
          </button>
        </div>

        <div
          v-if="form.brand_theme === 'custom'"
          class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-3.5"
        >
          <div
            class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end"
          >
            <label class="flex min-w-0 flex-col gap-1.5">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('THEME_SETTINGS.CUSTOM_COLOR') }}
              </span>
              <span class="flex min-w-0 gap-2">
                <input
                  :value="form.custom_brand_color"
                  type="color"
                  class="h-10 w-11 cursor-pointer rounded-lg border border-n-weak bg-n-solid-1 p-1"
                  :aria-label="t('THEME_SETTINGS.CUSTOM_COLOR')"
                  @input="setCustomColor($event.target.value)"
                />
                <input
                  :value="form.custom_brand_color"
                  type="text"
                  maxlength="7"
                  class="h-10 min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm uppercase text-n-slate-12 outline-none focus:border-n-brand"
                  @change="setCustomColor($event.target.value)"
                />
              </span>
            </label>
            <div
              class="flex h-10 items-center justify-center gap-1.5 rounded-lg px-3 text-xs"
              :class="
                hasAccessibleContrast
                  ? 'bg-n-teal-9/10 text-n-teal-11'
                  : 'bg-n-amber-9/10 text-n-amber-11'
              "
            >
              <span
                :class="
                  hasAccessibleContrast
                    ? 'i-lucide-shield-check'
                    : 'i-lucide-wand-sparkles'
                "
                class="size-4"
              />
              <span>
                {{
                  hasAccessibleContrast
                    ? t('THEME_SETTINGS.CONTRAST.APPROVED')
                    : t('THEME_SETTINGS.CONTRAST.WILL_ADJUST')
                }}
              </span>
            </div>
          </div>

          <div
            class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
          >
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('THEME_SETTINGS.INTENSITY.LABEL') }}
            </span>
            <div class="grid grid-cols-3 rounded-lg bg-n-alpha-2 p-1">
              <button
                v-for="option in intensityOptions"
                :key="option.value"
                type="button"
                class="rounded-md px-3 py-1.5 text-xs transition-colors"
                :class="
                  form.brand_intensity === option.value
                    ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                    : 'text-n-slate-11 hover:text-n-slate-12'
                "
                @click="form.brand_intensity = option.value"
              >
                {{ option.label }}
              </button>
            </div>
          </div>

          <button
            type="button"
            class="flex w-fit items-center gap-1 text-xs text-n-slate-11 hover:text-n-slate-12"
            @click="showAdvanced = !showAdvanced"
          >
            <span
              :class="
                showAdvanced
                  ? 'i-lucide-chevron-down'
                  : 'i-lucide-chevron-right'
              "
              class="size-4"
            />
            {{ t('THEME_SETTINGS.ADVANCED') }}
          </button>

          <div v-if="showAdvanced" class="grid gap-3 sm:grid-cols-2">
            <label
              class="flex items-center gap-2 sm:col-span-2"
              for="separate-dark-theme-color"
            >
              <input
                id="separate-dark-theme-color"
                v-model="form.custom_brand_color_dark_enabled"
                type="checkbox"
                class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
              />
              <span class="text-xs text-n-slate-11">
                {{ t('THEME_SETTINGS.SEPARATE_DARK_COLOR') }}
              </span>
            </label>
            <label class="flex flex-col gap-1.5">
              <span class="text-xs text-n-slate-11">
                {{ t('THEME_SETTINGS.LIGHT_COLOR') }}
              </span>
              <input
                :value="form.custom_brand_color"
                type="text"
                maxlength="7"
                class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm uppercase text-n-slate-12 outline-none focus:border-n-brand"
                @change="setCustomColor($event.target.value)"
              />
            </label>
            <label class="flex flex-col gap-1.5">
              <span class="text-xs text-n-slate-11">
                {{ t('THEME_SETTINGS.DARK_COLOR') }}
              </span>
              <input
                :value="form.custom_brand_color_dark"
                type="text"
                maxlength="7"
                class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm uppercase text-n-slate-12 outline-none focus:border-n-brand"
                :disabled="!form.custom_brand_color_dark_enabled"
                @change="setCustomDarkColor($event.target.value)"
              />
            </label>
          </div>
        </div>
      </section>

      <section
        class="grid gap-3 sm:grid-cols-[minmax(0,1.35fr)_minmax(160px,.65fr)]"
      >
        <div class="flex flex-col gap-2.5">
          <h4 class="text-sm font-medium text-n-slate-12">
            {{ t('THEME_SETTINGS.PREVIEW') }}
          </h4>
          <div
            class="theme-preview overflow-hidden rounded-xl border border-n-weak"
            :class="isPreviewDark ? 'is-dark' : 'is-light'"
            :style="previewStyle"
          >
            <div class="theme-preview__header">
              {{
                ['ViperChat', t('THEME_SETTINGS.PREVIEW_REAL_TIME')].join(' · ')
              }}
            </div>
            <div class="grid min-h-28 grid-cols-[88px_1fr]">
              <div class="theme-preview__sidebar border-r p-2">
                <div
                  class="theme-preview__selected rounded-md px-2 py-1.5 text-xs font-medium"
                >
                  {{ t('THEME_SETTINGS.PREVIEW_MINE') }}
                </div>
                <div class="theme-preview__muted px-2 py-1.5 text-xs">
                  {{ t('THEME_SETTINGS.PREVIEW_ALL') }}
                </div>
              </div>
              <div
                class="theme-preview__content flex flex-col justify-end gap-2 p-3"
              >
                <div
                  class="theme-preview__bubble ml-auto rounded-lg rounded-br-sm px-3 py-2 text-xs text-white"
                >
                  {{ t('THEME_SETTINGS.PREVIEW_MESSAGE') }}
                </div>
                <button
                  type="button"
                  class="theme-preview__button w-fit rounded-md px-2.5 py-1.5 text-xs text-white"
                >
                  {{ t('THEME_SETTINGS.PREVIEW_ACTION') }}
                </button>
              </div>
            </div>
          </div>
        </div>

        <div
          v-if="form.recent_brand_colors.length"
          class="flex flex-col justify-center rounded-xl border border-n-weak bg-n-alpha-1 p-3.5"
        >
          <span class="mb-2 text-xs font-medium text-n-slate-11">
            {{ t('THEME_SETTINGS.RECENT_COLORS') }}
          </span>
          <div class="mb-3 flex flex-wrap gap-2">
            <button
              v-for="color in form.recent_brand_colors"
              :key="color"
              type="button"
              class="size-7 rounded-full border-2 border-n-solid-1 ring-1 ring-n-weak"
              :style="{ backgroundColor: color }"
              :aria-label="color"
              @click="useRecentColor(color)"
            />
          </div>
          <p class="mb-0 text-xs text-n-slate-10">
            {{ t('THEME_SETTINGS.USER_SCOPED') }}
          </p>
        </div>
      </section>
    </div>

    <template #footer>
      <div
        class="flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <Button
          variant="ghost"
          color="slate"
          icon="i-lucide-rotate-ccw"
          :label="t('THEME_SETTINGS.RESTORE')"
          type="button"
          @click="restoreDefaults"
        />
        <div class="grid grid-cols-2 gap-2">
          <Button
            variant="faded"
            color="slate"
            :label="t('DIALOG.BUTTONS.CANCEL')"
            type="button"
            @click="close"
          />
          <Button
            color="blue"
            :label="t('THEME_SETTINGS.SAVE')"
            :is-loading="isSaving"
            :disabled="isSaving"
            type="button"
            @click="save"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>

<style scoped>
.theme-settings-dialog__body {
  -webkit-overflow-scrolling: touch;
}

.theme-custom-swatch {
  background: conic-gradient(
    from 45deg,
    #f43f5e,
    #f59e0b,
    #22c55e,
    #0ea5e9,
    #7c3aed,
    #f43f5e
  );
}

.theme-preview {
  --theme-preview-background: #f3f4f6;
  --theme-preview-surface: #ffffff;
  --theme-preview-text: #374151;
  --theme-preview-muted: #6b7280;
  --theme-preview-soft: color-mix(
    in srgb,
    var(--theme-preview-brand) 12%,
    #ffffff
  );
  background: var(--theme-preview-background);
  color: var(--theme-preview-text);
}

.theme-preview.is-dark {
  --theme-preview-background: #202126;
  --theme-preview-surface: #292b31;
  --theme-preview-text: #f3f4f6;
  --theme-preview-muted: #a5a8b0;
  --theme-preview-soft: color-mix(
    in srgb,
    var(--theme-preview-brand) 20%,
    #292b31
  );
}

.theme-preview__header,
.theme-preview__sidebar {
  background: var(--theme-preview-surface);
  border-color: color-mix(in srgb, var(--theme-preview-text) 12%, transparent);
}

.theme-preview__header {
  padding: 0.5rem 0.75rem;
  color: var(--theme-preview-muted);
  font-size: 0.6875rem;
}

.theme-preview__selected {
  background: var(--theme-preview-soft);
  color: var(--theme-preview-brand);
}

.theme-preview__muted {
  color: var(--theme-preview-muted);
}

.theme-preview__bubble,
.theme-preview__button {
  background: var(--theme-preview-brand);
}
</style>
