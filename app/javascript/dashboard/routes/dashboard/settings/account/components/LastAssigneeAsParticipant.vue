<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();
const enabled = ref(true);
const saving = ref(false);
watch(
  currentAccount,
  () => {
    enabled.value =
      currentAccount.value?.settings?.last_assignee_as_participant !== false;
  },
  { deep: true, immediate: true }
);

const save = async () => {
  saving.value = true;
  try {
    await updateAccount({ last_assignee_as_participant: enabled.value });
    useAlert(t('GENERAL_SETTINGS.FORM.LAST_ASSIGNEE_AS_PARTICIPANT.SUCCESS'));
  } catch {
    enabled.value = !enabled.value;
    useAlert(t('GENERAL_SETTINGS.FORM.LAST_ASSIGNEE_AS_PARTICIPANT.ERROR'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.LAST_ASSIGNEE_AS_PARTICIPANT.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.LAST_ASSIGNEE_AS_PARTICIPANT.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="enabled" :disabled="saving" @change="save" />
      </div>
    </template>
  </SectionLayout>
</template>
