<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { ATTACHMENT_TYPES } from '../constants';

const emit = defineEmits(['error']);
const retryDelays = [500, 1000, 2000, 4000, 8000, 16000, 32000, 64000];
const hasError = ref(false);
const showGallery = ref(false);
const cacheBust = ref(0);
const retryCount = ref(0);
let retryTimer;
const { filteredCurrentChatAttachments, attachments } = useMessageContext();

const clearRetryTimer = () => {
  if (retryTimer) {
    clearTimeout(retryTimer);
    retryTimer = null;
  }
};

const resetRetryState = () => {
  clearRetryTimer();
  hasError.value = false;
  retryCount.value = 0;
};

const attachment = computed(() => {
  return attachments.value[0];
});

const handleError = () => {
  const hasMoreRetries = retryCount.value < retryDelays.length;
  const hasValidUrl = !!attachment.value?.dataUrl;

  if (!hasMoreRetries || !hasValidUrl) {
    hasError.value = true;
    emit('error');
    return;
  }

  const delay = retryDelays[retryCount.value];
  retryCount.value += 1;

  clearRetryTimer();
  retryTimer = setTimeout(() => {
    cacheBust.value = Date.now();
  }, delay);
};

const videoSrc = computed(() => {
  const url = attachment.value?.dataUrl || '';
  if (!url) return '';

  if (!cacheBust.value) return url;

  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}t=${cacheBust.value}`;
});

const isReel = computed(() => {
  return attachment.value.fileType === ATTACHMENT_TYPES.IG_REEL;
});

const galleryAttachment = computed(() => useSnakeCase(attachment.value || {}));

const handleLoad = () => {
  hasError.value = false;
};

watch(
  () => attachment.value?.dataUrl,
  () => {
    resetRetryState();
    cacheBust.value = Date.now();
  }
);

onBeforeUnmount(clearRetryTimer);
</script>

<template>
  <BaseBubble
    class="overflow-hidden p-3"
    data-bubble-name="video"
    @click="showGallery = true"
  >
    <div class="relative group rounded-lg overflow-hidden">
      <div
        v-if="hasError"
        class="flex items-center gap-1 text-center rounded-lg"
      >
        <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
        <p class="mb-0 text-n-slate-11">
          {{ $t('COMPONENTS.MEDIA.VIDEO_UNAVAILABLE') }}
        </p>
      </div>
      <div
        v-else-if="isReel"
        class="absolute p-2 flex items-start justify-end right-0 pointer-events-none"
      >
        <Icon icon="i-lucide-instagram" class="text-white shadow-lg" />
      </div>
      <video
        v-if="!hasError"
        controls
        class="rounded-lg skip-context-menu"
        :src="videoSrc"
        :class="{
          'max-w-48': isReel,
          'max-w-full': !isReel,
        }"
        @click.stop
        @loadeddata="handleLoad"
        @error="handleError"
      />
    </div>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="galleryAttachment"
    :all-attachments="filteredCurrentChatAttachments"
    @error="handleError"
    @close="() => (showGallery = false)"
  />
</template>
