<script setup>
import { onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';

const props = defineProps({ stream: { type: Object, required: true } });
const { t } = useI18n();
const container = ref(null);
let waveform;
let microphone;
const failed = ref(false);

onMounted(() => {
  try {
    const record = RecordPlugin.create({
      scrollingWaveform: true,
      renderRecordedAudio: false,
    });
    waveform = WaveSurfer.create({
      container: container.value,
      height: 48,
      barWidth: 2,
      barGap: 1,
      barRadius: 2,
      waveColor: getComputedStyle(container.value).color,
      plugins: [record],
    });
    // Visualize the existing stream; do not request a second microphone or recorder.
    microphone = record.renderMicStream(props.stream);
  } catch {
    failed.value = true;
  }
});
onUnmounted(() => {
  microphone?.onDestroy();
  waveform?.destroy();
});
</script>

<template>
  <div class="min-w-0 w-full text-n-blue-11">
    <div ref="container" role="img" :aria-label="t('waveform')" />
    <p v-if="failed" role="status" class="text-sm text-n-slate-11">
      {{ t('waveformUnavailable') }}
    </p>
  </div>
</template>
