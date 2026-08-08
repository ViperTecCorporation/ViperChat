<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const useLegacyComposer = ref(false);
const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    useLegacyComposer.value =
      currentAccount.value?.settings?.use_legacy_message_composer === true;
  },
  { deep: true, immediate: true }
);

const updateComposerPreference = async () => {
  try {
    await updateAccount({
      use_legacy_message_composer: useLegacyComposer.value,
    });
    useAlert(t('GENERAL_SETTINGS.FORM.MESSAGE_COMPOSER.API.SUCCESS'));
  } catch (error) {
    useLegacyComposer.value = !useLegacyComposer.value;
    useAlert(t('GENERAL_SETTINGS.FORM.MESSAGE_COMPOSER.API.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.MESSAGE_COMPOSER.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.MESSAGE_COMPOSER.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch
          v-model="useLegacyComposer"
          @change="updateComposerPreference"
        />
      </div>
    </template>
  </SectionLayout>
</template>
