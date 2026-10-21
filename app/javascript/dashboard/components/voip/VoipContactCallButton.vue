<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAgentVoipStore } from 'dashboard/stores/agentVoip';

const props = defineProps({
  contact: { type: Object, default: () => ({}) },
  size: { type: String, default: 'sm' },
});

const { t } = useI18n();
const phone = useAgentVoipStore();
const address = computed(() => {
  const attributes =
    props.contact.additional_attributes ||
    props.contact.additionalAttributes ||
    {};
  if (
    props.contact.group ||
    props.contact.is_group ||
    attributes.group ||
    attributes.is_group ||
    [props.contact.email, props.contact.identifier].some(value =>
      String(value || '').endsWith('@g.us')
    )
  ) {
    return '';
  }
  const value = String(
    props.contact.phone_number || props.contact.phoneNumber || ''
  ).trim();
  // Provider IDs (LID, BSUID, group JID) are not telephone destinations.
  if (!/^\+?[\d\s().-]+$/.test(value)) return '';
  const normalized = value.replace(/[\s().-]/g, '');
  return /^\+?\d{7,15}$/.test(normalized) ? normalized : '';
});

const openDialer = () => {
  if (!address.value) return;
  phone.openDialer({
    address: address.value,
    serviceId: null,
    kind: 'manual',
  });
};
</script>

<template>
  <button
    v-if="address"
    type="button"
    class="inline-flex shrink-0 items-center justify-center rounded-full text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    :class="size === 'xs' ? 'size-8' : 'size-10'"
    :aria-label="t('AGENT_VOIP.NEW_CALL')"
    :title="t('AGENT_VOIP.NEW_CALL')"
    data-voip-contact-call
    @click.stop.prevent="openDialer"
  >
    <span class="i-lucide-phone size-5" aria-hidden="true" />
  </button>
</template>
