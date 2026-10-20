<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();
const enabled = ref(false);
const saving = ref(false);
watch(
  currentAccount,
  account => {
    enabled.value = account?.settings?.allow_agents_to_create_labels === true;
  },
  { immediate: true, deep: true }
);

const save = async () => {
  if (saving.value) return;
  saving.value = true;
  try {
    await updateAccount({ allow_agents_to_create_labels: enabled.value });
    useAlert(t('GENERAL_SETTINGS.FORM.AGENT_LABEL_CREATION.SUCCESS'));
  } catch {
    enabled.value =
      currentAccount.value?.settings?.allow_agents_to_create_labels === true;
    useAlert(t('GENERAL_SETTINGS.FORM.AGENT_LABEL_CREATION.ERROR'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.AGENT_LABEL_CREATION.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.AGENT_LABEL_CREATION.NOTE')"
    with-border
  >
    <template #headerActions>
      <label
        class="min-h-11 w-11 ms-auto flex items-center justify-end cursor-pointer"
      >
        <Switch
          v-model="enabled"
          :aria-label="t('GENERAL_SETTINGS.FORM.AGENT_LABEL_CREATION.TITLE')"
          :disabled="saving"
          @change="save"
        />
      </label>
    </template>
  </SectionLayout>
</template>
