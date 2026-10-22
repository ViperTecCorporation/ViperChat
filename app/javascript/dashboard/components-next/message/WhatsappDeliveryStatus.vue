<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  attributes: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const rows = computed(() =>
  Object.entries(
    props.attributes.whatsapp_delivery ||
      props.attributes.whatsappDelivery ||
      {}
  )
    .map(([provider, row]) => [
      provider === 'whatsappCloud' ? 'whatsapp_cloud' : provider,
      row,
    ])
    .filter(([provider]) => ['unoapi', 'whatsapp_cloud'].includes(provider))
);
const blocked = computed(() => {
  const transport =
    props.attributes.whatsapp_transport ||
    props.attributes.whatsappTransport ||
    {};
  return transport.fallback_blocked_reason || transport.fallbackBlockedReason;
});
const icons = {
  failed: 'i-lucide-triangle-alert',
  uncertain: 'i-lucide-circle-help',
  progress: 'i-lucide-loader-circle',
  sent: 'i-lucide-check',
  delivered: 'i-lucide-check-check',
  read: 'i-lucide-check-check',
  skipped: 'i-lucide-minus',
};
const hasNotice = computed(
  () =>
    rows.value.length > 1 ||
    rows.value.some(([, row]) => ['failed', 'uncertain'].includes(row.state)) ||
    blocked.value
);
const stateLabel = row => (row.origin === 'echo' ? 'observed' : row.state);
</script>

<template>
  <div
    v-if="hasNotice"
    role="status"
    class="mt-2 flex min-w-0 flex-col gap-1 break-words text-xs"
    :aria-label="t('CONVERSATION.PROVIDER_DELIVERY.TITLE')"
  >
    <div
      v-for="[provider, row] in rows"
      :key="provider"
      class="flex min-w-0 items-start gap-1.5"
      :class="
        ['failed', 'uncertain'].includes(row.state)
          ? 'text-n-ruby-11'
          : 'text-n-slate-11'
      "
    >
      <span
        :class="icons[row.state] || 'i-lucide-circle-help'"
        class="mt-0.5 block size-3 shrink-0"
        aria-hidden="true"
      />
      <span class="min-w-0">
        {{ t(`CONVERSATION.PROVIDER_DELIVERY.PROVIDER.${provider}`) }}:
        {{ t(`CONVERSATION.PROVIDER_DELIVERY.STATE.${stateLabel(row)}`) }}
        <span v-if="row.error" class="block whitespace-pre-wrap">{{
          row.error
        }}</span>
      </span>
    </div>
    <p v-if="blocked" class="m-0 text-n-ruby-11">
      {{ t(`CONVERSATION.PROVIDER_DELIVERY.BLOCKED.${blocked}`) }}
    </p>
  </div>
</template>
