<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  contentAttributes: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const warnings = computed(() => {
  const values =
    props.contentAttributes.unoapiWarnings ??
    props.contentAttributes.unoapi_warnings;
  return Array.isArray(values) ? values.filter(value => value?.code) : [];
});
const warningText = warning =>
  warning.code === 'REPLY_SENT_WITHOUT_QUOTE'
    ? t('CONVERSATION.UNOAPI_WARNING.WITHOUT_QUOTE')
    : warning.message || warning.code;
</script>

<template>
  <details
    v-if="warnings.length"
    class="mt-1 min-w-0 max-w-lg rounded-lg text-xs text-n-amber-11"
    @click.stop
    @touchstart.stop
  >
    <summary
      class="flex min-h-8 cursor-pointer items-center gap-1 px-2"
      :title="warnings.map(warningText).join('\n')"
    >
      <span
        class="i-lucide-triangle-alert size-4 shrink-0"
        aria-hidden="true"
      />
      {{ t('CONVERSATION.UNOAPI_WARNING.TITLE') }}
    </summary>
    <ul
      class="m-0 list-none space-y-1 break-words px-2 pb-2 [overflow-wrap:anywhere]"
    >
      <li v-for="warning in warnings" :key="warning.code">
        {{ warningText(warning) }}
      </li>
    </ul>
  </details>
</template>
