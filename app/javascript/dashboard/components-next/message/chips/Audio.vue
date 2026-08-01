<script setup>
import {
  computed,
  onMounted,
  useTemplateRef,
  ref,
  getCurrentInstance,
  watch,
  onBeforeUnmount,
} from 'vue';
import Icon from 'next/icon/Icon.vue';
import { downloadFile } from '@chatwoot/utils';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';

const { attachment } = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
  showTranscribedText: {
    type: Boolean,
    default: true,
  },
});

defineOptions({
  inheritAttrs: false,
});

const audioPlayer = useTemplateRef('audioPlayer');
const { orientation } = useMessageContext();

const shouldLog =
  (import.meta.env?.VITE_CONSOLE_LOG ?? 'true').toString().toLowerCase() ===
  'true';
const logDebug = (...args) => {
  if (shouldLog) {
    // eslint-disable-next-line no-console
    console.log('[AudioChip]', ...args);
  }
};

const retryDelays = [500, 1000, 2000, 4000, 8000, 16000, 32000, 64000];
const isPlaying = ref(false);
const isMuted = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const playbackSpeed = ref(1);
const cacheBust = ref(0);
const retryCount = ref(0);
const resumeTime = ref(0);
const resumeOnLoad = ref(false);
let retryTimer;
let metadataTimer;

const { uid } = getCurrentInstance();

const formatTime = time => {
  if (!time || Number.isNaN(time)) return '00:00';
  const minutes = Math.floor(time / 60);
  const seconds = Math.floor(time % 60);
  return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
};

const isReadyToPlay = computed(() => {
  return Number.isFinite(duration.value) && duration.value > 0;
});

const displayCurrentTime = computed(() => {
  return isReadyToPlay.value ? formatTime(currentTime.value) : '00:00';
});

const displayDuration = computed(() => {
  return isReadyToPlay.value ? formatTime(duration.value) : '--:--';
});

const scheduleReload = () => {
  const hasValidUrl = !!attachment.dataUrl;
  const hasRetries = retryCount.value < retryDelays.length;

  if (!hasValidUrl || !hasRetries) {
    logDebug('scheduleReload aborted', { hasValidUrl, hasRetries });
    isPlaying.value = false;
    duration.value = 0;
    currentTime.value = 0;
    return;
  }

  const delay = retryDelays[retryCount.value];
  retryCount.value += 1;

  clearRetryTimer();
  retryTimer = setTimeout(() => {
    cacheBust.value = Date.now();
    audioPlayer.value?.load();
    logDebug('retrying audio load', {
      retryCount: retryCount.value,
      cacheBust: cacheBust.value,
    });
  }, delay);
};

const clearRetryTimer = () => {
  if (retryTimer) {
    clearTimeout(retryTimer);
    retryTimer = null;
  }
};

const clearMetadataTimer = () => {
  if (metadataTimer) {
    clearTimeout(metadataTimer);
    metadataTimer = null;
  }
};

const scheduleMetadataTimeout = () => {
  clearMetadataTimer();
  metadataTimer = setTimeout(() => {
    if (!isReadyToPlay.value) {
      handlePlaybackError();
    }
  }, 1500);
};

const resetRetryState = () => {
  clearRetryTimer();
  clearMetadataTimer();
  retryCount.value = 0;
  resumeTime.value = 0;
  resumeOnLoad.value = false;
};

const audioSrc = computed(() => {
  const url = attachment.dataUrl || '';
  if (!url) return '';

  if (!cacheBust.value) return url;

  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}t=${cacheBust.value}`;
});

const onLoadedMetadata = () => {
  const player = audioPlayer.value;
  const metaDuration = player?.duration;
  duration.value = Number.isFinite(metaDuration) ? metaDuration : 0;
  clearMetadataTimer();
  logDebug('loadedmetadata', {
    duration: duration.value,
    src: audioSrc.value,
  });
  if (player) {
    player.playbackRate = playbackSpeed.value;
  }
  if (resumeTime.value && player) {
    audioPlayer.value.currentTime = Math.min(
      resumeTime.value,
      audioPlayer.value.duration || resumeTime.value
    );
  }

  if (resumeOnLoad.value && audioSrc.value) {
    audioPlayer.value
      ?.play()
      .then(() => {
        isPlaying.value = true;
      })
      .catch(() => {
        isPlaying.value = false;
      })
      .finally(() => {
        resumeOnLoad.value = false;
      });
  }

  resetRetryState();

  if (!isReadyToPlay.value) {
    scheduleMetadataTimeout();
  }
};

const playbackSpeedLabel = computed(() => {
  return `${playbackSpeed.value}x`;
});

const isOutgoing = computed(() => orientation.value === 'right');

const containerClass = computed(() =>
  isOutgoing.value
    ? 'bg-n-solid-blue border-n-blue-5 text-n-slate-12'
    : 'bg-n-blue-2 border-n-blue-4 text-n-blue-12'
);

const speedButtonClass = computed(() =>
  isOutgoing.value
    ? 'bg-n-blue-10/20 hover:bg-n-blue-10/30'
    : 'bg-n-blue-3 hover:bg-n-blue-4'
);

const transcriptionClass = computed(() =>
  isOutgoing.value
    ? 'text-n-slate-12 bg-n-blue-10/20'
    : 'text-n-blue-12 bg-n-blue-3'
);

// There maybe a chance that the audioPlayer ref is not available
// When the onLoadMetadata is called, so we need to set the duration
// value when the component is mounted
onMounted(() => {
  duration.value = audioPlayer.value?.duration;
  audioPlayer.value.playbackRate = playbackSpeed.value;
});

// Listen for global audio play events and pause if it's not this audio
useEmitter('pause_playing_audio', currentPlayingId => {
  if (currentPlayingId !== uid && isPlaying.value) {
    try {
      audioPlayer.value.pause();
    } catch {
      /* ignore pause errors */
    }
    isPlaying.value = false;
  }
});

const toggleMute = () => {
  audioPlayer.value.muted = !audioPlayer.value.muted;
  isMuted.value = audioPlayer.value.muted;
};

const onTimeUpdate = () => {
  currentTime.value = audioPlayer.value?.currentTime;
};

const seek = event => {
  const time = Number(event.target.value);
  audioPlayer.value.currentTime = time;
  currentTime.value = time;
};

const playOrPause = () => {
  if (isPlaying.value) {
    audioPlayer.value.pause();
    isPlaying.value = false;
  } else {
    if (!isReadyToPlay.value) {
      resumeOnLoad.value = true;
      scheduleReload();
      return;
    }
    // Emit event to pause all other audio
    emitter.emit('pause_playing_audio', uid);
    audioPlayer.value.play();
    isPlaying.value = true;
  }
};

const onEnd = () => {
  isPlaying.value = false;
  currentTime.value = 0;
  playbackSpeed.value = 1;
  audioPlayer.value.playbackRate = 1;
};

const changePlaybackSpeed = () => {
  const speeds = [1, 1.5, 2];
  const currentIndex = speeds.indexOf(playbackSpeed.value);
  const nextIndex = (currentIndex + 1) % speeds.length;
  playbackSpeed.value = speeds[nextIndex];
  audioPlayer.value.playbackRate = playbackSpeed.value;
};

const downloadAudio = async () => {
  const { fileType, dataUrl, extension } = attachment;
  downloadFile({ url: dataUrl, type: fileType, extension });
};

const handlePlaybackError = () => {
  const hasValidUrl = !!attachment.dataUrl;
  const hasRetries = retryCount.value < retryDelays.length;

  if (!hasValidUrl || !hasRetries) {
    logDebug('scheduleReload aborted', { hasValidUrl, hasRetries });
    isPlaying.value = false;
    duration.value = 0;
    currentTime.value = 0;
    return;
  }

  resumeTime.value = audioPlayer.value?.currentTime || 0;
  resumeOnLoad.value = isPlaying.value;
  isPlaying.value = false;

  scheduleReload();
  logDebug('handlePlaybackError', {
    resumeTime: resumeTime.value,
    retryCount: retryCount.value,
  });
};

watch(audioSrc, newSrc => {
  if (!newSrc) return;

  // reload the element to fetch the fresh source
  audioPlayer.value?.load();
  scheduleMetadataTimeout();
});

watch(
  () => attachment.dataUrl,
  () => {
    duration.value = 0;
    currentTime.value = 0;
    resetRetryState();
    cacheBust.value = Date.now();
    audioPlayer.value?.load();
    scheduleMetadataTimeout();
  }
);

onBeforeUnmount(() => {
  clearRetryTimer();
  clearMetadataTimer();
});
</script>

<template>
  <audio
    ref="audioPlayer"
    controls
    class="hidden"
    playsinline
    preload="metadata"
    @loadedmetadata="onLoadedMetadata"
    @loadeddata="clearMetadataTimer"
    @canplay="clearMetadataTimer"
    @timeupdate="onTimeUpdate"
    @ended="onEnd"
    @error="handlePlaybackError"
    @stalled="handlePlaybackError"
  >
    <source :src="audioSrc" />
  </audio>
  <div
    v-bind="$attrs"
    class="rounded-xl w-full gap-2 p-1.5 flex flex-col items-center border shadow-[0px_2px_8px_0px_rgba(94,94,94,0.06)]"
    :class="containerClass"
  >
    <div class="flex gap-1 w-full flex-1 items-center justify-start">
      <button class="p-0 border-0 size-8" @click="playOrPause">
        <Icon
          v-if="isReadyToPlay && isPlaying"
          class="size-8"
          icon="i-teenyicons-pause-small-solid"
        />
        <Icon v-else class="size-8" icon="i-teenyicons-play-small-solid" />
      </button>
      <div class="tabular-nums text-xs">
        {{ displayCurrentTime }} / {{ displayDuration }}
      </div>
      <div class="flex-1 items-center flex px-2">
        <input
          type="range"
          min="0"
          :max="isReadyToPlay ? duration : 0"
          :value="isReadyToPlay ? currentTime : 0"
          class="w-full h-1 bg-n-slate-12/40 rounded-lg appearance-none cursor-pointer accent-current disabled:cursor-not-allowed"
          :disabled="!isReadyToPlay"
          @input="seek"
        />
      </div>
      <button
        class="border-0 w-10 h-6 grid place-content-center rounded-2xl"
        :class="speedButtonClass"
        @click="changePlaybackSpeed"
      >
        <span class="text-xs font-medium">
          {{ playbackSpeedLabel }}
        </span>
      </button>
      <button
        class="p-0 border-0 size-8 grid place-content-center"
        @click="toggleMute"
      >
        <Icon v-if="isMuted" class="size-4" icon="i-lucide-volume-off" />
        <Icon v-else class="size-4" icon="i-lucide-volume-2" />
      </button>
      <button
        class="p-0 border-0 size-8 grid place-content-center"
        @click="downloadAudio"
      >
        <Icon class="size-4" icon="i-lucide-download" />
      </button>
    </div>

    <div
      v-if="attachment.transcribedText && showTranscribedText"
      class="p-3 text-sm rounded-lg w-full break-words"
      :class="transcriptionClass"
    >
      {{ attachment.transcribedText }}
    </div>
  </div>
</template>
