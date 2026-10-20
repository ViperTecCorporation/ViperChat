<script setup>
import { computed } from 'vue';
import { getWhatsappInboxLink } from '../helpers/whatsappUnifiedInbox';

const props = defineProps({
  inbox: { type: Object, default: null },
  contact: { type: Object, default: null },
  disabled: { type: Boolean, default: false },
});
const provider = defineModel({ type: String, default: '' });
const link = computed(() => getWhatsappInboxLink(props.inbox, props.contact));
</script>

<template>
  <div>
    <label
      v-if="link"
      class="flex min-w-0 flex-wrap items-center gap-2 px-4 py-3 text-sm text-n-slate-11"
    >
      <span>{{ $t('WHATSAPP_UNIFIED.SEND_VIA') }}</span>
      <select
        v-model="provider"
        :disabled="disabled"
        class="mb-0 min-h-11 min-w-0 max-w-full flex-1 rounded-md border border-n-strong bg-n-solid-1 text-base sm:text-sm text-n-slate-12"
      >
        <option disabled value="">{{ $t('WHATSAPP_UNIFIED.CHOOSE') }}</option>
        <option
          v-for="transport in link.transports"
          :key="transport.provider"
          :value="transport.provider"
          :disabled="!['unoapi', 'whatsapp_cloud'].includes(transport.provider)"
        >
          {{ transport.label }}
        </option>
      </select>
    </label>
  </div>
</template>
