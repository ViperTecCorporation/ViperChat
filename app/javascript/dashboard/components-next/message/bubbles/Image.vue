<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BaseBubble from './Base.vue';
import Button from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import { downloadFile } from '@chatwoot/utils';

import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const emit = defineEmits(['error']);

const { t } = useI18n();

const { filteredCurrentChatAttachments, attachments } = useMessageContext();
const attachment = computed(() => {
  // pick the first image-like attachment
  return (
    attachments.value.find(item => item?.fileType === 'image') ||
    attachments.value[0]
  );
});
const galleryAttachment = computed(() => useSnakeCase(attachment.value || {}));

const retryDelays = [500, 1000, 2000, 4000, 8000, 16000, 32000, 64000];
const hasError = ref(false);
const showGallery = ref(false);
const isDownloading = ref(false);
const hasLoaded = ref(false);
const cacheBust = ref(0);
const retryCount = ref(0);
let retryTimer;

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
  const url = attachment.value?.dataUrl || attachment.value?.thumbUrl || '';
  if (!url) return '';

  if (!cacheBust.value) return url;

  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}t=${cacheBust.value}`;
});

const handleError = () => {
  const hasMoreRetries = retryCount.value < retryDelays.length;
  const hasValidUrl = !!attachment.value?.dataUrl;

  if (!hasMoreRetries || !hasValidUrl) {
    hasError.value = true;
    emit('error');
    return;
  }

  hasLoaded.value = false;
  const delay = retryDelays[retryCount.value];
  retryCount.value += 1;

  clearRetryTimer();
  retryTimer = setTimeout(() => {
    cacheBust.value = Date.now();
  }, delay);
};

const handleLoad = () => {
  hasError.value = false;
  hasLoaded.value = true;
};

const downloadAttachment = async () => {
  const { fileType, dataUrl, thumbUrl, extension } = attachment.value;
  try {
    isDownloading.value = true;
    await downloadFile({ url: dataUrl || thumbUrl, type: fileType, extension });
  } catch (error) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    isDownloading.value = false;
  }
};

watch(
  () => attachment.value?.dataUrl || attachment.value?.thumbUrl,
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
    data-bubble-name="image"
    @click="showGallery = true"
  >
    <div v-if="hasError" class="flex items-center gap-1 text-center rounded-lg">
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      <p class="mb-0 text-n-slate-11">
        {{ $t('COMPONENTS.MEDIA.IMAGE_UNAVAILABLE') }}
      </p>
    </div>
    <div v-else class="relative group rounded-lg overflow-hidden">
      <img
        class="skip-context-menu"
        :src="imageSrc"
        :width="attachment.width"
        :height="attachment.height"
        @load="handleLoad"
        @error="handleError"
      />
      <div
        class="inset-0 p-2 pointer-events-none absolute bg-gradient-to-tl from-n-slate-12/30 dark:from-n-slate-1/50 via-transparent to-transparent hidden group-hover:flex"
      />
      <div class="absolute right-2 bottom-2 hidden group-hover:flex gap-2">
        <Button xs solid slate icon="i-lucide-expand" class="opacity-60" />
        <Button
          xs
          solid
          slate
          icon="i-lucide-download"
          class="opacity-60"
          :is-loading="isDownloading"
          :disabled="isDownloading"
          @click.stop="downloadAttachment"
        />
      </div>
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
