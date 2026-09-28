<script setup>
defineProps({
  modelValue: { type: String, default: 'none' },
  disabled: Boolean,
});
defineEmits(['update:modelValue']);
const periods = ['none', '7d', '30d', '3m', '6m', '12m'];
</script>

<template>
  <label class="block w-full max-w-xl mb-4">
    <span>{{ $t('INBOX_MGMT.GMAIL_HISTORY.TITLE') }}</span>
    <select
      :value="modelValue"
      :disabled="disabled"
      class="w-full mt-2"
      @change="$emit('update:modelValue', $event.target.value)"
    >
      <option v-for="period in periods" :key="period" :value="period">
        {{ $t(`INBOX_MGMT.GMAIL_HISTORY.PERIODS.${period}`) }}
      </option>
    </select>
    <span class="block text-sm font-normal text-n-slate-11">
      {{ $t('INBOX_MGMT.GMAIL_HISTORY.HELP') }}
    </span>
  </label>
</template>
