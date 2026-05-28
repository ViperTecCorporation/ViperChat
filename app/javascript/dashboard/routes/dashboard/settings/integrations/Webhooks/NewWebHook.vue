<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useBranding } from 'shared/composables/useBranding';
import WebhookForm from './WebhookForm.vue';

const props = defineProps({
  onClose: {
    type: Function,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const { replaceInstallationName } = useBranding();

const uiFlags = computed(() => store.getters['webhooks/getUIFlags']);

const onSubmit = async webhook => {
  try {
    await store.dispatch('webhooks/create', { webhook });
    useAlert(t('INTEGRATION_SETTINGS.WEBHOOK.ADD.API.SUCCESS_MESSAGE'));
    props.onClose();
  } catch (error) {
    const message =
      error.response.data.message ||
      t('INTEGRATION_SETTINGS.WEBHOOK.EDIT.API.ERROR_MESSAGE');
    useAlert(message);
  }
};
</script>

<template>
  <div class="h-auto overflow-auto flex flex-col">
    <woot-modal-header
      :header-title="t('INTEGRATION_SETTINGS.WEBHOOK.ADD.TITLE')"
      :header-content="
        replaceInstallationName(t('INTEGRATION_SETTINGS.WEBHOOK.FORM.DESC'))
      "
    />
    <WebhookForm
      :is-submitting="uiFlags.creatingItem"
      :submit-label="t('INTEGRATION_SETTINGS.WEBHOOK.FORM.ADD_SUBMIT')"
      @submit="onSubmit"
      @cancel="props.onClose()"
    />
  </div>
</template>
