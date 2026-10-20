<script setup>
defineProps({
  modelValue: { type: String, default: '' },
  options: { type: Object, default: null },
  legacy: { type: Boolean, default: false },
});
defineEmits(['update:modelValue']);
</script>

<template>
  <div v-if="options" class="flex flex-col min-w-0 gap-2">
    <label
      class="flex flex-col min-w-0 gap-1.5 text-sm font-medium text-n-slate-12"
    >
      {{ $t('WHATSAPP_UNIFIED.SCHEDULE.PROVIDER') }}
      <select
        :value="modelValue"
        class="w-full min-w-0 h-10 px-3 rounded-lg border border-n-weak bg-n-solid-2 text-n-slate-12 focus:border-n-brand"
        data-testid="scheduled-whatsapp-provider"
        @change="$emit('update:modelValue', $event.target.value)"
      >
        <option disabled value="">{{ $t('WHATSAPP_UNIFIED.CHOOSE') }}</option>
        <option
          v-for="transport in options.transports"
          :key="transport.provider"
          :value="transport.provider"
        >
          {{
            transport.provider === 'unoapi'
              ? $t('WHATSAPP_UNIFIED.VIPERCONNECT')
              : $t('WHATSAPP_UNIFIED.META')
          }}
        </option>
      </select>
    </label>
    <p class="mb-0 text-xs break-words text-n-slate-11">
      {{ $t('WHATSAPP_UNIFIED.SCHEDULE.HELP') }}
    </p>
    <p v-if="legacy" class="mb-0 text-xs break-words text-n-amber-11">
      {{ $t('WHATSAPP_UNIFIED.SCHEDULE.LEGACY_HELP') }}
    </p>
  </div>
</template>
