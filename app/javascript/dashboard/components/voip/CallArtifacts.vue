<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { VoipAPI } from 'dashboard/api/voip';
import AudioChip from 'next/message/chips/Audio.vue';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  callId: { type: [Number, String], required: true },
  artifacts: { type: Object, default: null },
});
const { t } = useI18n();
const audioUrl = ref('');
const loading = ref(false);
const error = ref(false);
let requestVersion = 0;
const recording = computed(() => props.artifacts?.recording);
const ai = computed(() => props.artifacts?.ai);
const audioAttachment = computed(() => ({
  dataUrl: audioUrl.value,
  fileType: 'audio',
  extension: recording.value?.mime_type === 'audio/mpeg' ? 'mp3' : 'wav',
}));
const noteLink = computed(() => {
  const id = props.artifacts?.conversation_id;
  const messageId = props.artifacts?.message_id;
  if (!/^\d+$/.test(String(id)) || !/^\d+$/.test(String(messageId)))
    return null;
  return `/app/accounts/${props.accountId}/conversations/${id}?messageId=${messageId}`;
});
function releaseAudio() {
  if (audioUrl.value) URL.revokeObjectURL(audioUrl.value);
  audioUrl.value = '';
}
watch(
  () => [props.accountId, props.callId, recording.value?.record_id],
  () => {
    requestVersion += 1;
    releaseAudio();
    loading.value = false;
    error.value = false;
  }
);
onBeforeUnmount(() => {
  requestVersion += 1;
  releaseAudio();
});
async function loadRecording() {
  if (loading.value) return;
  requestVersion += 1;
  const version = requestVersion;
  loading.value = true;
  error.value = false;
  try {
    const { data } = await new VoipAPI(props.accountId).recording(props.callId);
    if (version !== requestVersion) return;
    releaseAudio();
    audioUrl.value = URL.createObjectURL(data);
  } catch {
    if (version === requestVersion) error.value = true;
  } finally {
    if (version === requestVersion) loading.value = false;
  }
}
</script>

<template>
  <section
    v-if="artifacts"
    :aria-label="t('AGENT_VOIP.ARTIFACTS.TITLE')"
    class="flex min-w-0 flex-col gap-4 rounded-2xl border border-n-weak p-4"
  >
    <h3 class="flex items-center gap-2 font-semibold">
      <span aria-hidden="true" class="i-lucide-file-audio size-5 shrink-0" />
      {{ t('AGENT_VOIP.ARTIFACTS.TITLE') }}
    </h3>
    <div v-if="recording" class="flex min-w-0 flex-col gap-2">
      <p class="flex flex-wrap items-center gap-2 text-sm">
        <span class="font-medium">{{
          t('AGENT_VOIP.ARTIFACTS.RECORDING')
        }}</span>
        <span role="status" class="text-n-slate-11">
          {{ t(`AGENT_VOIP.ARTIFACTS.STATUS.${recording.status}`) }}
        </span>
      </p>
      <button
        v-if="artifacts.recording_available && !audioUrl"
        type="button"
        :disabled="loading"
        class="inline-flex min-h-11 items-center justify-center gap-2 self-start rounded-full border border-n-weak px-4 text-sm disabled:opacity-50"
        @click="loadRecording"
      >
        <span aria-hidden="true" class="i-lucide-headphones size-4 shrink-0" />
        {{
          t(
            loading
              ? 'AGENT_VOIP.ARTIFACTS.LOADING'
              : 'AGENT_VOIP.ARTIFACTS.LISTEN'
          )
        }}
      </button>
      <template v-if="audioUrl">
        <AudioChip
          :attachment="audioAttachment"
          orientation="left"
          compact
          :show-transcribed-text="false"
          class="min-w-0 max-w-full"
        />
      </template>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ t('AGENT_VOIP.ARTIFACTS.LOAD_ERROR') }}
      </p>
    </div>
    <div v-if="ai" class="flex min-w-0 flex-col gap-3">
      <p class="flex flex-wrap items-center gap-2 text-sm">
        <span aria-hidden="true" class="i-lucide-sparkles size-4 shrink-0" />
        <span class="font-medium">{{ t('AGENT_VOIP.ARTIFACTS.AI') }}</span>
        <span role="status" class="text-n-slate-11">
          {{ t(`AGENT_VOIP.ARTIFACTS.STATUS.${ai.status}`) }}
        </span>
      </p>
      <div v-if="ai.summary" class="min-w-0">
        <h4 class="mb-1 text-sm font-medium">
          {{ t('AGENT_VOIP.ARTIFACTS.SUMMARY') }}
        </h4>
        <p class="whitespace-pre-wrap break-words text-sm">{{ ai.summary }}</p>
      </div>
      <details v-if="ai.transcript" class="min-w-0 text-sm">
        <summary class="min-h-11 cursor-pointer py-3 font-medium">
          {{ t('AGENT_VOIP.ARTIFACTS.TRANSCRIPT') }}
        </summary>
        <p class="whitespace-pre-wrap break-words">{{ ai.transcript }}</p>
      </details>
    </div>
    <RouterLink
      v-if="noteLink"
      :to="noteLink"
      class="inline-flex min-h-11 items-center gap-2 self-start break-words text-sm text-n-brand"
    >
      <span
        aria-hidden="true"
        class="i-lucide-message-square-lock size-4 shrink-0"
      />
      {{ t('AGENT_VOIP.ARTIFACTS.OPEN_NOTE') }}
    </RouterLink>
    <p
      v-else-if="artifacts.publication_state"
      role="status"
      class="text-xs text-n-slate-11"
    >
      {{ t(`AGENT_VOIP.ARTIFACTS.PUBLICATION.${artifacts.publication_state}`) }}
    </p>
  </section>
</template>
