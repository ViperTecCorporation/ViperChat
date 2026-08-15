<script setup>
defineProps({
  label: {
    type: String,
    required: true,
  },
  help: {
    type: String,
    required: true,
  },
});
</script>

<template>
  <span class="inline-flex items-center gap-1.5">
    <span>{{ label }}</span>
    <i
      v-tooltip.top="help"
      class="i-lucide-circle-help size-3.5 shrink-0 cursor-help text-slate-500"
      tabindex="0"
      role="img"
      :aria-label="help"
    />
  </span>
</template>
