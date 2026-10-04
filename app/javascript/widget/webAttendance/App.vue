<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Message from './Message.vue';
import RecordingWaveform from './RecordingWaveform.vue';
import { useAttendance } from './useAttendance';

const props = defineProps({ invitation: { type: String, default: null } });
const { t } = useI18n();
const {
  authenticated,
  messages,
  name,
  contactName,
  state,
  hasMore,
  loadingOlder,
  draft,
  files,
  sending,
  error,
  recording,
  startingRecording,
  canRecord,
  voiceUrl,
  recordingStream,
  cancelRecording,
  removeVoice,
  refresh,
  older,
  send,
  addFiles,
  removeFile,
  startRecording,
  stopRecording,
} = useAttendance(props.invitation);
const list = ref(null);
const picker = ref(null);
const closed = computed(() => ['ended', 'unavailable'].includes(state.value));
const errorText = computed(
  () =>
    ({
      limit: t('limit'),
      failed: t('failed'),
      rejected: t('rejected'),
      microphone: t('microphone'),
    })[error.value] || ''
);
const canSend = computed(
  () =>
    authenticated.value &&
    !sending.value &&
    !recording.value &&
    !startingRecording.value &&
    (draft.value.trim() || files.value.length)
);

function selectFiles(event) {
  addFiles(Array.from(event.target.files || []));
  event.target.value = '';
}

function onMessageKeydown(event) {
  if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
  event.preventDefault();
  if (canSend.value) send();
}

async function loadOlder() {
  const height = list.value?.scrollHeight || 0;
  const top = list.value?.scrollTop || 0;
  await older();
  nextTick(() => {
    if (list.value)
      list.value.scrollTop = top + list.value.scrollHeight - height;
  });
}

watch(
  () => messages.value.at(-1)?.id,
  () => {
    const element = list.value;
    const nearBottom =
      !element ||
      element.scrollHeight - element.scrollTop - element.clientHeight < 120;
    if (nearBottom)
      nextTick(() => {
        if (list.value) list.value.scrollTop = list.value.scrollHeight;
      });
  }
);
</script>

<template>
  <main
    class="fixed inset-0 flex min-w-0 flex-col overflow-hidden bg-n-background font-sans text-n-slate-12"
  >
    <div
      class="mx-auto flex h-full w-full min-w-0 max-w-3xl flex-col pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)]"
    >
      <header class="shrink-0 border-b border-n-weak px-4 py-3">
        <h1 class="break-words text-lg font-semibold">
          {{ name || t('title') }}
        </h1>
        <p v-if="contactName" class="break-words text-sm text-n-slate-11">
          {{ contactName }}
        </p>
      </header>
      <div
        v-if="state === 'offline'"
        role="status"
        class="shrink-0 border-b border-n-weak px-4 py-2 text-sm"
      >
        <p>{{ t('offline') }}</p>
        <button
          type="button"
          class="min-h-11 font-medium underline"
          @click="refresh"
        >
          {{ t('retry') }}
        </button>
      </div>
      <div
        v-if="closed"
        role="status"
        class="flex flex-1 flex-col items-center justify-center gap-3 p-6 text-center"
      >
        <h2 class="text-lg font-semibold">
          {{ state === 'ended' ? t('ended') : t('unavailable') }}
        </h2>
        <p v-if="state === 'ended'">{{ t('invite') }}</p>
      </div>
      <template v-else>
        <section
          ref="list"
          :aria-label="t('history')"
          class="min-h-0 flex-1 space-y-3 overflow-y-auto overscroll-contain px-3 py-4 sm:px-6"
        >
          <p v-if="state === 'loading'" role="status" class="text-center">
            {{ t('loading') }}
          </p>
          <button
            v-if="hasMore"
            type="button"
            :disabled="loadingOlder"
            class="mx-auto block min-h-11 rounded-lg border border-n-weak px-3 text-sm disabled:opacity-50"
            @click="loadOlder"
          >
            {{ t('older') }}
          </button>
          <Message
            v-for="message in messages"
            :key="message.id"
            :message="message"
          />
        </section>
        <form
          class="shrink-0 space-y-2 border-t border-n-weak px-3 py-3"
          @submit.prevent="send"
        >
          <p v-if="error" role="alert" class="break-words text-sm">
            {{ errorText }}
          </p>
          <ul v-if="files.length" class="max-h-24 space-y-1 overflow-y-auto">
            <li
              v-for="(file, index) in files"
              :key="index"
              class="flex min-w-0 items-center gap-2 text-sm"
            >
              <span class="min-w-0 flex-1 truncate">{{ file.name }}</span>
              <button
                type="button"
                :disabled="sending"
                class="min-h-11 shrink-0 px-2 underline"
                :aria-label="`${t('remove')}: ${file.name}`"
                @click="removeFile(index)"
              >
                {{ t('remove') }}
              </button>
            </li>
          </ul>
          <audio
            v-if="voiceUrl"
            :src="voiceUrl"
            controls
            class="h-10 w-full max-w-full"
            :aria-label="t('voice')"
          />
          <button
            v-if="voiceUrl"
            type="button"
            :disabled="sending"
            class="min-h-11 px-2 text-sm underline disabled:opacity-50"
            @click="removeVoice"
          >
            {{ t('removeVoice') }}
          </button>
          <RecordingWaveform v-if="recordingStream" :stream="recordingStream" />
          <p v-if="recording" role="status" class="text-sm">
            {{ t('recording') }}
          </p>
          <textarea
            v-model="draft"
            rows="2"
            :disabled="sending || state === 'loading'"
            :aria-label="t('message')"
            :placeholder="t('message')"
            class="max-h-32 min-h-12 w-full resize-none text-base"
            @keydown="onMessageKeydown"
          />
          <div class="flex min-w-0 flex-wrap items-center gap-2">
            <input
              ref="picker"
              type="file"
              multiple
              class="reset-base hidden"
              :disabled="
                sending || recording || startingRecording || state === 'loading'
              "
              @change="selectFiles"
            />
            <button
              type="button"
              :disabled="
                sending || recording || startingRecording || state === 'loading'
              "
              class="min-h-11 rounded-lg border border-n-weak px-3 text-sm disabled:opacity-50"
              @click="picker?.click()"
            >
              {{ t('attach') }}
            </button>
            <button
              v-if="canRecord"
              type="button"
              :disabled="
                sending ||
                startingRecording ||
                state === 'loading' ||
                Boolean(voiceUrl) ||
                (!recording && files.length >= 5)
              "
              class="min-h-11 rounded-lg border border-n-weak px-3 text-sm disabled:opacity-50"
              @click="recording ? stopRecording() : startRecording()"
            >
              {{ recording ? t('stop') : t('record') }}
            </button>
            <button
              v-if="recording || startingRecording"
              type="button"
              class="min-h-11 rounded-lg border border-n-weak px-3 text-sm"
              @click="cancelRecording"
            >
              {{ t('cancelRecording') }}
            </button>
            <button
              type="submit"
              :disabled="!canSend"
              class="ml-auto min-h-11 rounded-lg px-4 text-sm font-medium disabled:opacity-50"
              :class="
                canSend
                  ? 'bg-n-brand text-white'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              {{ sending ? t('sending') : t('send') }}
            </button>
          </div>
        </form>
      </template>
    </div>
  </main>
</template>
