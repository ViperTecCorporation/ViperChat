<script setup>
import { useMediaQuery } from '@vueuse/core';

defineProps({
  modelValue: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});

defineEmits(['update:modelValue']);

const showTooltip = useMediaQuery(
  '(min-width: 640px) and (hover: hover) and (pointer: fine)'
);
</script>

<template>
  <button
    v-tooltip.top="{
      content: $t(
        modelValue
          ? 'CONVERSATION.VIEW_ONCE_DISABLE'
          : 'CONVERSATION.VIEW_ONCE_ENABLE'
      ),
      disabled: !showTooltip,
    }"
    type="button"
    :aria-label="
      $t(
        modelValue
          ? 'CONVERSATION.VIEW_ONCE_DISABLE'
          : 'CONVERSATION.VIEW_ONCE_ENABLE'
      )
    "
    :aria-pressed="modelValue"
    :disabled="disabled"
    class="flex size-8 shrink-0 items-center justify-center rounded-full border-0 p-0 disabled:opacity-50"
    :class="modelValue ? 'bg-n-brand text-white' : 'bg-n-alpha-2 text-current'"
    @click="$emit('update:modelValue', !modelValue)"
  >
    <svg
      viewBox="0 0 24 24"
      class="size-5"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      aria-hidden="true"
    >
      <path d="M12 3a9 9 0 0 0 0 18" stroke-linecap="round" />
      <path
        d="M15 3.5a9 9 0 0 1 0 17"
        stroke-dasharray="1 3.5"
        stroke-linecap="round"
      />
      <path d="m10 9 2-1v8" stroke-linecap="round" stroke-linejoin="round" />
    </svg>
  </button>
</template>
