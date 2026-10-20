<script setup>
defineProps({
  modelValue: { type: String, default: '' },
  transports: { type: Array, required: true },
  disabled: { type: Boolean, default: false },
});
defineEmits(['update:modelValue']);
</script>

<template>
  <label
    class="flex min-w-0 w-full flex-wrap items-center gap-2 text-sm text-n-slate-12"
  >
    <span class="shrink-0">{{ $t('WHATSAPP_UNIFIED.SEND_VIA') }}</span>
    <select
      :value="modelValue"
      :disabled="disabled"
      class="!m-0 min-w-0 flex-1 sm:flex-none sm:w-auto !h-10 !text-sm"
      @change="$emit('update:modelValue', $event.target.value)"
    >
      <option
        v-for="transport in transports"
        :key="transport.provider"
        :value="transport.provider"
      >
        {{ transport.label }}
      </option>
    </select>
    <span
      v-if="
        transports.find(item => item.provider === modelValue)?.can_reply ===
        false
      "
      class="w-full min-w-0 break-words text-xs text-n-slate-11"
      role="status"
    >
      {{ $t('WHATSAPP_UNIFIED.UNAVAILABLE') }}
    </span>
  </label>
</template>
