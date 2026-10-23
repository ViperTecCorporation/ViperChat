<script setup>
import { computed } from 'vue';
import { useBreakpoints } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../provider';
import BaseBubble from './Base.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import AudioChip from '../chips/Audio.vue';
import { formatDuration } from 'shared/helpers/timeHelper';

const { t } = useI18n();
const { contentAttributes, attachments } = useMessageContext();
const compactAudio = useBreakpoints({ mobile: 480 }).smaller('mobile');
const data = computed(() => contentAttributes.value?.data || {});
const state = computed(() => data.value.state);
const missed = computed(() =>
  ['missed', 'failed', 'cancelled'].includes(state.value)
);
const icon = computed(() =>
  missed.value ? 'i-ph-phone-x-bold' : 'i-ph-phone-call-bold'
);
const audio = computed(() =>
  attachments.value?.find(item => item.fileType === 'audio')
);
const duration = computed(
  () => data.value.durationSeconds ?? data.value.duration_seconds
);
const service = computed(
  () => data.value.serviceName || data.value.service_name
);
const analysis = computed(
  () =>
    contentAttributes.value?.voipCallAnalysis ||
    contentAttributes.value?.voip_call_analysis ||
    {}
);
const analysisSections = computed(() =>
  ['summary', 'transcript'].filter(section => analysis.value[section])
);
const directionLabel = computed(() =>
  t(
    data.value.direction === 'outbound'
      ? 'AGENT_VOIP.CALL_EVENT.OUTBOUND'
      : 'AGENT_VOIP.CALL_EVENT.INBOUND'
  )
);
const summary = computed(() => `${service.value} · ${directionLabel.value}`);
const extensionSummary = computed(
  () => `${t('AGENT_VOIP.EXTENSION')} ${data.value.extension}`
);
</script>

<template>
  <BaseBubble
    class="!max-w-md !bg-n-brand/10 !p-3 !text-n-slate-12 border border-n-brand/30"
    hide-meta
  >
    <div class="flex w-full min-w-0 flex-col gap-3">
      <div class="flex items-start gap-2.5">
        <div
          class="flex size-11 shrink-0 items-center justify-center rounded-xl"
          :class="
            missed ? 'bg-n-alpha-2 text-n-ruby-9' : 'bg-n-brand/10 text-n-brand'
          "
        >
          <Icon class="size-4" :icon="icon" />
        </div>
        <div class="flex min-w-0 flex-1 flex-col gap-1 self-center text-sm">
          <span class="break-words font-medium">{{
            t(`AGENT_VOIP.CALL_EVENT.${state}`)
          }}</span>
          <span class="break-words opacity-75">
            {{ summary }}
          </span>
          <span v-if="data.extension" class="opacity-75">
            {{ extensionSummary }}
          </span>
          <span v-if="duration != null" class="opacity-75">{{
            formatDuration(duration)
          }}</span>
        </div>
      </div>
      <AudioChip
        v-if="audio"
        :attachment="audio"
        :compact="compactAudio"
        :show-transcribed-text="false"
      />
      <details
        v-for="section in analysisSections"
        :key="section"
        class="min-w-0 rounded-lg border border-n-weak p-2 text-sm"
      >
        <summary class="cursor-pointer select-none font-medium">
          {{ t(`AGENT_VOIP.ARTIFACTS.${section.toUpperCase()}`) }}
        </summary>
        <div
          class="mt-2 max-h-64 overflow-y-auto whitespace-pre-wrap break-words [overflow-wrap:anywhere]"
        >
          {{ analysis[section] }}
        </div>
      </details>
    </div>
  </BaseBubble>
</template>
