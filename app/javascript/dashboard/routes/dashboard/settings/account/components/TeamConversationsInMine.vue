<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const isEnabled = ref(true);
const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    isEnabled.value =
      currentAccount.value?.settings?.include_team_conversations_in_mine !==
      false;
  },
  { deep: true, immediate: true }
);

const updatePreference = async () => {
  try {
    await updateAccount({
      include_team_conversations_in_mine: isEnabled.value,
    });
    useAlert(t('GENERAL_SETTINGS.FORM.TEAM_CONVERSATIONS_IN_MINE.API.SUCCESS'));
  } catch (error) {
    isEnabled.value = !isEnabled.value;
    useAlert(t('GENERAL_SETTINGS.FORM.TEAM_CONVERSATIONS_IN_MINE.API.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.TEAM_CONVERSATIONS_IN_MINE.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.TEAM_CONVERSATIONS_IN_MINE.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="updatePreference" />
      </div>
    </template>
  </SectionLayout>
</template>
