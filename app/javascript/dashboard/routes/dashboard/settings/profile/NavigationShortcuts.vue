<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  DEFAULT_NAVIGATION_SHORTCUTS,
  navigationShortcuts,
  shortcutFromEvent,
} from 'dashboard/helper/navigationShortcuts';
import Button from 'dashboard/components-next/button/Button.vue';
import SectionLayout from '../account/components/SectionLayout.vue';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const shortcuts = ref(navigationShortcuts(uiSettings.value));
const saving = ref(false);
const feedback = ref('');
function capture(event, action) {
  if (event.key === 'Tab') return;
  event.preventDefault();
  event.stopPropagation();
  const shortcut = shortcutFromEvent(event);
  if (!shortcut) return;
  if (
    Object.entries(shortcuts.value).some(
      ([key, value]) => key !== action && value === shortcut
    )
  ) {
    feedback.value = 'DUPLICATE';
    return;
  }
  shortcuts.value[action] = shortcut;
  feedback.value = '';
}
async function save() {
  saving.value = true;
  try {
    const result = await updateUISettings({
      navigation_shortcuts: { ...shortcuts.value },
    });
    feedback.value = result === false ? 'ERROR' : 'SAVED';
  } catch {
    feedback.value = 'ERROR';
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <SectionLayout
    :title="t('PROFILE_SETTINGS.NAVIGATION_SHORTCUTS.TITLE')"
    :description="t('PROFILE_SETTINGS.NAVIGATION_SHORTCUTS.DESCRIPTION')"
    with-border
  >
    <div class="flex flex-col gap-4 w-full min-w-0">
      <label
        v-for="(_, action) in DEFAULT_NAVIGATION_SHORTCUTS"
        :key="action"
        class="flex flex-wrap items-center gap-2 w-full"
      >
        <span class="grow basis-40">{{
          t(`PROFILE_SETTINGS.NAVIGATION_SHORTCUTS.ACTIONS.${action}`)
        }}</span>
        <input
          :value="shortcuts[action]"
          readonly
          :disabled="saving"
          class="!mb-0 !w-40 max-w-full"
          :aria-label="
            t(`PROFILE_SETTINGS.NAVIGATION_SHORTCUTS.ACTIONS.${action}`)
          "
          @keydown="capture($event, action)"
        />
      </label>
      <p v-if="feedback" role="status" class="text-sm">
        {{ t(`PROFILE_SETTINGS.NAVIGATION_SHORTCUTS.${feedback}`) }}
      </p>
      <div class="flex flex-wrap gap-2">
        <Button
          :label="t('PROFILE_SETTINGS.NAVIGATION_SHORTCUTS.SAVE')"
          :disabled="saving"
          @click="save"
        />
        <Button
          :label="t('PROFILE_SETTINGS.NAVIGATION_SHORTCUTS.RESET')"
          variant="outline"
          :disabled="saving"
          @click="
            shortcuts = { ...DEFAULT_NAVIGATION_SHORTCUTS };
            feedback = '';
          "
        />
      </div>
    </div>
  </SectionLayout>
</template>
