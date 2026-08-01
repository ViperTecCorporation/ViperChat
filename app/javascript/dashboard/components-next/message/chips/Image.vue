<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';

import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const props = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
});
const attachment = computed(() => props.attachment || {});
const galleryAttachment = computed(() => {
  try {
    return useSnakeCase(attachment.value) || attachment.value;
  } catch {
    return attachment.value;
  }
});
const shouldLog =
  (import.meta.env?.VITE_CONSOLE_LOG ?? 'true').toString().toLowerCase() ===
  'true';
const logDebug = (...args) => {
  if (shouldLog) {
    // eslint-disable-next-line no-console
    console.log('[ImageChip]', ...args);
  }
};

const retryDelays = [500, 1000, 2000, 4000, 8000, 16000, 32000, 64000];
const hasError = ref(false);
const showGallery = ref(false);
const cacheBust = ref(0);
const retryCount = ref(0);
let retryTimer;

const { filteredCurrentChatAttachments } = useMessageContext();

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

const imageSrc = computed(() => {
  const url = attachment.value?.dataUrl || '';
  if (!url) return '';
  if (!cacheBust.value) return url;

  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}t=${cacheBust.value}`;
});

const handleError = () => {
  const hasMoreRetries = retryCount.value < retryDelays.length;
  const hasValidUrl = !!attachment.value?.dataUrl;

  if (!hasMoreRetries || !hasValidUrl) {
    logDebug('handleError aborted', { hasMoreRetries, hasValidUrl });
    hasError.value = true;
    return;
  }

  const delay = retryDelays[retryCount.value];
  retryCount.value += 1;

  clearRetryTimer();
  retryTimer = setTimeout(() => {
    cacheBust.value = Date.now();
    logDebug('retrying image load', {
      retryCount: retryCount.value,
      cacheBust: cacheBust.value,
    });
  }, delay);
};

watch(
  () => attachment.value?.dataUrl,
  () => {
    resetRetryState();
    cacheBust.value = Date.now();
    logDebug('dataUrl changed', {
      dataUrl: attachment.value?.dataUrl,
      thumbUrl: attachment.value?.thumbUrl,
    });
  }
);

watch(
  () => showGallery.value,
  value => {
    if (!value) return;
    logDebug('opening gallery', {
      attachment: attachment.value,
      filteredCurrentChatAttachmentsCount:
        filteredCurrentChatAttachments.value.length,
    });
  }
);

onBeforeUnmount(clearRetryTimer);
</script>

<template>
  <div
    class="size-[72px] overflow-hidden contain-content rounded-xl cursor-pointer"
    @click="showGallery = true"
  >
    <div
      v-if="hasError"
      class="flex flex-col items-center justify-center gap-1 text-xs text-center rounded-lg size-full bg-n-alpha-1 text-n-slate-11"
    >
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      {{ $t('COMPONENTS.MEDIA.LOADING_FAILED') }}
    </div>
    <img
      v-else
      class="object-cover w-full h-full skip-context-menu"
      :src="imageSrc"
      @error="handleError"
    />
  </div>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="galleryAttachment"
    :all-attachments="filteredCurrentChatAttachments"
    @error="handleError"
    @close="() => (showGallery = false)"
  />
</template>
