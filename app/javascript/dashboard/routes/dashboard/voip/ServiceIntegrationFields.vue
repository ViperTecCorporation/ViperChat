<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const form = defineModel({ type: Object, required: true });
const { t } = useI18n();
const providers = ['none', 'webhook', 'viperconnect'];
const copyStatus = ref('');
watch(
  () => form.value.webhook_url,
  () => {
    copyStatus.value = '';
  }
);
async function copyWebhookUrl() {
  try {
    await copyTextToClipboard(form.value.webhook_url);
    copyStatus.value = 'WEBHOOK_COPIED';
  } catch {
    copyStatus.value = 'WEBHOOK_COPY_FAILED';
  }
}
</script>

<template>
  <fieldset
    class="m-0 flex min-w-0 flex-col gap-4 rounded-xl border border-n-weak p-3 sm:p-4"
  >
    <legend class="px-1 text-sm font-semibold">
      {{ t('AGENT_VOIP.INTEGRATION') }}
    </legend>
    <label class="flex min-w-0 flex-col gap-1 text-sm">
      {{ t('AGENT_VOIP.INTEGRATION_PROVIDER') }}
      <select
        v-model="form.integration_provider"
        name="integration_provider"
        class="min-w-0 w-full rounded-lg border border-n-weak bg-n-surface-2 p-2"
      >
        <option v-for="provider in providers" :key="provider" :value="provider">
          {{ t(`AGENT_VOIP.PROVIDERS.${provider}`) }}
        </option>
      </select>
    </label>
    <template v-if="form.integration_provider !== 'none'">
      <p class="m-0 text-xs text-n-slate-11">
        {{ t('AGENT_VOIP.INTEGRATION_PENDING') }}
      </p>
      <label class="flex min-w-0 flex-col gap-1 text-sm">
        {{ t('AGENT_VOIP.WEBHOOK_SOURCE') }}
        <input
          v-model="form.webhook_source_instance_id"
          name="webhook_source_instance_id"
          required
          maxlength="128"
          autocomplete="off"
          class="min-w-0 w-full rounded-lg border border-n-weak bg-n-surface-2 p-2"
        />
      </label>
      <p class="m-0 text-xs text-n-slate-11">
        {{ t('AGENT_VOIP.WEBHOOK_SOURCE_HELP') }}
      </p>
      <template v-if="form.webhook_url">
        <label class="flex min-w-0 flex-col gap-1 text-sm">
          {{ t('AGENT_VOIP.WEBHOOK_URL') }}
          <textarea
            :value="form.webhook_url"
            name="webhook_url"
            readonly
            rows="3"
            class="min-w-0 w-full resize-none rounded-lg border border-n-weak bg-n-surface-2 p-2 text-xs"
          />
        </label>
        <button
          type="button"
          class="min-h-11 self-start rounded-lg border border-n-weak px-3 text-sm"
          @click="copyWebhookUrl"
        >
          {{ t('AGENT_VOIP.WEBHOOK_COPY') }}
        </button>
        <p v-if="copyStatus" role="status" class="m-0 text-xs text-n-slate-11">
          {{ t(`AGENT_VOIP.${copyStatus}`) }}
        </p>
      </template>
      <p v-else class="m-0 text-xs text-n-slate-11">
        {{ t('AGENT_VOIP.WEBHOOK_SAVE_FIRST') }}
      </p>
      <p class="m-0 break-words text-xs text-n-slate-11">
        {{ t('AGENT_VOIP.WEBHOOK_AUTH_HELP') }}
      </p>
      <template v-if="form.integration_provider === 'viperconnect'">
        <h3 class="text-sm font-semibold">
          {{ t('AGENT_VOIP.HISTORY_REST') }}
        </h3>
        <label class="flex min-w-0 flex-col gap-1 text-sm">
          {{ t('AGENT_VOIP.HISTORY_COMPANY') }}
          <input
            v-model="form.history_company_id"
            name="history_company_id"
            required
            maxlength="128"
            autocomplete="off"
            class="min-w-0 w-full rounded-lg border border-n-weak bg-n-surface-2 p-2"
          />
        </label>
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('AGENT_VOIP.HISTORY_COMPANY_HELP') }}
        </p>
        <label class="flex min-w-0 flex-col gap-1 text-sm">
          {{ t('AGENT_VOIP.HISTORY_URL') }}
          <input
            v-model="form.history_api_url"
            name="history_api_url"
            required
            type="url"
            :placeholder="t('AGENT_VOIP.HISTORY_URL_EXAMPLE')"
            autocomplete="off"
            class="min-w-0 w-full rounded-lg border border-n-weak bg-n-surface-2 p-2"
          />
        </label>
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('AGENT_VOIP.HISTORY_REST_HELP') }}
        </p>
        <label class="flex min-w-0 flex-col gap-1 text-sm">
          {{ t('AGENT_VOIP.HISTORY_TOKEN') }}
          <input
            v-model="form.history_api_token"
            name="history_api_token"
            type="password"
            autocomplete="new-password"
            :disabled="form.clear_history_api_token"
            :placeholder="
              form.history_api_token_configured
                ? t('AGENT_VOIP.SECRET_SAVED')
                : ''
            "
            class="min-w-0 w-full rounded-lg border border-n-weak bg-n-surface-2 p-2"
          />
        </label>
        <label
          v-if="form.history_api_token_configured"
          class="flex items-center gap-2 text-sm"
        >
          <input
            v-model="form.clear_history_api_token"
            name="clear_history_api_token"
            type="checkbox"
          />
          {{ t('AGENT_VOIP.CLEAR_HISTORY_TOKEN') }}
        </label>
      </template>
    </template>
  </fieldset>
</template>
